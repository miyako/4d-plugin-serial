#include "4DPlugin-Serial.h"
#include "ARRAY_TEXT.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include <cassert>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>

// Link only inert stand-ins: accidentally reaching device discovery is fatal.
@implementation ORSSerialPort
@dynamic delegate;
+ (ORSSerialPort *)existingPortWithPath:(NSString *)path { abort(); }
@end
@implementation ORSSerialPortManager
+ (ORSSerialPortManager *)sharedSerialPortManager { abort(); }
@end
NSString * const ORSSerialPortsWereConnectedNotification = @"connected";
NSString * const ORSSerialPortsWereDisconnectedNotification = @"disconnected";
NSString * const ORSConnectedSerialPortsKey = @"connected";
NSString * const ORSDisconnectedSerialPortsKey = @"disconnected";

namespace SERIAL {
extern NSMutableArray<NSData *> *SERIAL_DATA;
extern NSMutableArray<NSString *> *SERIAL_PATH;
extern C_TEXT LISTENER_METHOD;
}

static std::set<PA_Unichar *> strings;
static std::map<PA_Handle, size_t> handles;
struct Object {
    size_t refs = 1;
    std::map<CUTF16String, PA_Variable> properties;
};
struct ShimCollection { size_t refs = 1; };
static std::set<Object *> objects;
static std::set<ShimCollection *> collections;
static bool nullEmpty;
static bool methodBranch;
static bool copyInput;
static PA_VariableKind returnKind;
static CUTF16String expected;
static CUTF8String expectedUTF8;
static CUTF16String methodName;
static const unsigned char bytes[] = {0, 1, 0x80, 0xff};

static CUTF16String text(const PA_Unistring &s)
{
    auto buffer = s.fString;
    if (!buffer) { assert(s.fLength == 0); return {}; }
    assert(strings.count(buffer));
    assert(buffer[s.fLength] == 0);
    return CUTF16String(buffer, s.fLength);
}

static PA_Unistring makeString(const CUTF16String &s)
{
    PA_Unistring result = {};
    result.fLength = static_cast<PA_long32>(s.size());
    if (s.empty() && nullEmpty) return result;
    result.fString = static_cast<PA_Unichar *>(calloc(s.size() + 1, sizeof(PA_Unichar)));
    assert(result.fString);
    memcpy(result.fString, s.data(), s.size() * sizeof(PA_Unichar));
    auto buffer = result.fString;
    assert(strings.insert(buffer).second);
    return result;
}

static void dispose(PA_Unistring &s)
{
    auto buffer = s.fString;
    if (buffer) {
        assert(strings.erase(buffer) == 1);
        free(buffer);
    }
    s = {};
}

static void clear(PA_Variable &v);
static PA_Variable copy(PA_Variable v)
{
    if (v.fType == eVK_Unistring) v.uValue.fString = makeString(text(v.uValue.fString));
    if (v.fType == eVK_Object && v.uValue.fObject)
        ++static_cast<Object *>(v.uValue.fObject)->refs;
    if (v.fType == eVK_Collection && v.uValue.fCollection)
        ++static_cast<ShimCollection *>(v.uValue.fCollection)->refs;
    return v;
}

static void clear(PA_Variable &v)
{
    switch (v.fType) {
        case eVK_Unistring: dispose(v.uValue.fString); break;
        case eVK_Blob: PA_DisposeHandle(v.uValue.fBlob.fHandle); break;
        case eVK_ArrayUnicode: {
            auto elements = reinterpret_cast<PA_Unistring *>(*v.uValue.fArray.fData);
            for (int i = 0; i <= v.uValue.fArray.fNbElements; ++i) dispose(elements[i]);
            PA_DisposeHandle(v.uValue.fArray.fData);
            break;
        }
        case eVK_Object: {
            auto o = static_cast<Object *>(v.uValue.fObject);
            if (o && !--o->refs) {
                for (auto &item : o->properties) clear(item.second);
                assert(objects.erase(o) == 1);
                delete o;
            }
            break;
        }
        case eVK_Collection: {
            auto c = static_cast<ShimCollection *>(v.uValue.fCollection);
            if (c && !--c->refs) { assert(collections.erase(c) == 1); delete c; }
            break;
        }
        default: break;
    }
    v = {};
    v.fType = eVK_Undefined;
}

static PA_Variable value(PA_VariableKind kind)
{
    PA_Variable v = {};
    v.fType = kind;
    switch (kind) {
        case eVK_Unistring: v.uValue.fString = makeString(expected); break;
        case eVK_Object: {
            auto o = new Object;
            objects.insert(o);
            v.uValue.fObject = o;
            break;
        }
        case eVK_Collection: {
            auto c = new ShimCollection;
            collections.insert(c);
            v.uValue.fCollection = c;
            break;
        }
        case eVK_Boolean: v.uValue.fBoolean = 1; break;
        case eVK_Real: v.uValue.fReal = 115200; break;
        case eVK_Blob:
            PA_SetBlobVariable(&v, const_cast<unsigned char *>(bytes), sizeof(bytes));
            break;
        default: break;
    }
    return v;
}

static void balanced()
{
    if (!strings.empty() || !handles.empty() || !objects.empty() || !collections.empty()) {
        fprintf(stderr, "ownership imbalance: strings=%zu handles=%zu objects=%zu collections=%zu\n",
                strings.size(), handles.size(), objects.size(), collections.size());
        abort();
    }
}

static PA_Variable callback(PA_Variable *params, int count)
{
    assert(count == (methodBranch ? 2 : 3));
    int pathIndex = methodBranch ? 0 : 1;
    if (!methodBranch) assert(text(params[0].uValue.fString) == methodName);
    assert(params[pathIndex].fType == eVK_Unistring);
    assert(text(params[pathIndex].uValue.fString) == expected);
    auto &blob = params[pathIndex + 1].uValue.fBlob;
    assert(blob.fSize == sizeof(bytes));
    assert(memcmp(PA_LockHandle(blob.fHandle), bytes, sizeof(bytes)) == 0);
    PA_UnlockHandle(blob.fHandle);
    if (copyInput) {
        auto result = copy(params[pathIndex]);
        if (!expected.empty())
            assert(result.uValue.fString.fString != params[pathIndex].uValue.fString.fString);
        return result;
    }
    return value(returnKind);
}

static void engine(short selector, EngineBlock *eb)
{
    switch (selector) {
        case EX_CREATE_UNISTRING: {
            auto s = reinterpret_cast<PA_Unichar *>(eb->fHandle);
            eb->fUniString1 = makeString(CUTF16String(s));
            break;
        }
        case EX_SET_UNISTRING: {
            CUTF16String s(reinterpret_cast<PA_Unichar *>(eb->fHandle));
            dispose(eb->fUniString1);
            eb->fUniString1 = makeString(s);
            break;
        }
        case EX_DISPOSE_UNISTRING: dispose(eb->fUniString1); break;
        case EX_VARIABLE_TO_STRING: {
            auto v = reinterpret_cast<PA_Variable *>(eb->fHandle);
            assert(v->fType == eVK_Unistring);
            eb->fUniString1 = v->uValue.fString;
            break;
        }
        case EX_CONVERT_STRING:
            assert(eb->fParam1 == 5 && eb->fParam2 == 0);
            eb->fHandle = PA_NewHandle(eb->fParam4);
            memcpy(*eb->fHandle, reinterpret_cast<void *>(eb->fParam3), eb->fParam4);
            break;
        case EX_CLEAR_VARIABLE: clear(*static_cast<PA_Variable *>(eb->fPtr1)); break;
        case EX_HANDLE_MANAGER: {
            auto handle = eb->fHandle;
            switch (eb->fParam1) {
                case 1: {
                    auto h = static_cast<PA_Handle>(malloc(sizeof(char *)));
                    *h = static_cast<char *>(calloc(1, eb->fParam2 ? eb->fParam2 : 1));
                    handles[h] = eb->fParam2;
                    eb->fHandle = h;
                    break;
                }
                case 2:
                    assert(handles.erase(handle) == 1);
                    free(*handle);
                    free(handle);
                    break;
                case 3:
                    assert(handles.count(handle));
                    *handle = static_cast<char *>(realloc(*handle, eb->fParam2));
                    handles[handle] = eb->fParam2;
                    break;
                case 4: eb->fParam2 = handles.at(handle); break;
                case 5: eb->fParam3 = reinterpret_cast<sLONG_PTR>(*handle); break;
                case 6: break;
                default: abort();
            }
            break;
        }
        case EX_GET_METHOD_ID:
            assert(CUTF16String(eb->fUName) == methodName);
            eb->fParam1 = methodBranch ? 42 : 0;
            break;
        case EX_CALL_BY_PROCID: {
            auto args = reinterpret_cast<PA_Variable *>(*eb->fHandle);
            args[0] = callback(args + 1, eb->fParam2);
            break;
        }
        case EX_EXECUTE_COMMAND_BY_ID: {
            auto args = static_cast<PA_Variable **>(eb->fPtr1);
            auto result = static_cast<PA_Variable *>(eb->fPtr2);
            switch (eb->fParam1) {
                case 1007: *result = callback(args[0], eb->fParam2); break;
                case 1231: {
                    auto o = static_cast<Object *>(args[0]->uValue.fObject);
                    result->fType = eVK_Boolean;
                    result->uValue.fBoolean = o->properties.count(text(args[1]->uValue.fString));
                    break;
                }
                default: abort();
            }
            break;
        }
        case EX_SET_OBJ_VALUE: {
            auto o = static_cast<Object *>(eb->fPtr1);
            auto key = text(eb->fUniString1);
            auto found = o->properties.find(key);
            if (found != o->properties.end()) clear(found->second);
            o->properties[key] = copy(*static_cast<PA_Variable *>(eb->fPtr2));
            break;
        }
        case EX_GET_OBJ_VALUE: {
            auto o = static_cast<Object *>(eb->fPtr1);
            *static_cast<PA_Variable *>(eb->fPtr2) = copy(o->properties.at(text(eb->fUniString1)));
            break;
        }
        default:
            fprintf(stderr, "unexpected engine selector: %d\n", selector);
            abort();
    }
}

static CUTF8String utf8(const CUTF16String &s)
{
    C_TEXT t;
    t.setUTF16String(s.data(), s.size());
    CUTF8String result;
    t.copyUTF8String(&result);
    return result;
}

static void setters()
{
    auto v = value(eVK_Object);
    auto o = static_cast<Object *>(v.uValue.fObject);
    const char *s = reinterpret_cast<const char *>(expectedUTF8.c_str());
    ob_set_s(o, "key", s);
    assert(text(o->properties.begin()->second.uValue.fString) == expected);
    ob_set_s(o, L"key", s);
    assert(text(o->properties.begin()->second.uValue.fString) == expected);
    ob_set_a(o, L"key", &expected);
    assert(text(o->properties.begin()->second.uValue.fString) == expected);
    NSString *ns = [NSString stringWithCharacters:expected.data() length:expected.size()];
    NSData *wide = [ns dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    std::vector<wchar_t> w([wide length] / sizeof(wchar_t) + 1);
    memcpy(w.data(), [wide bytes], [wide length]);
    ob_set_a(o, L"key", w.data());
    assert(text(o->properties.begin()->second.uValue.fString) == expected);
    clear(v);
}

static void properties()
{
    for (auto kind : {eVK_Unistring, eVK_Boolean, eVK_Real, eVK_Object, eVK_Collection}) {
        auto owner = value(eVK_Object);
        auto o = static_cast<Object *>(owner.uValue.fObject);
        CUTF16String key;
        json_wconv(L"key", &key);
        o->properties[key] = value(kind);
        CUTF8String s;
        assert(ob_get_a(o, L"key", &s));
        if (kind == eVK_Unistring) assert(s == expectedUTF8);
        assert(ob_get_b(o, L"key") == (kind == eVK_Boolean));
        assert(ob_get_n(o, L"key") == (kind == eVK_Real ? 115200 : 0));
        if (kind != eVK_Collection) assert(!ob_get_c(o, L"key"));
        assert(!ob_get_a(o, L"missing", &s));
        assert(!ob_get_b(o, L"missing"));
        assert(ob_get_n(o, L"missing") == 0);
        assert(!ob_get_c(o, L"missing"));
        clear(owner);
        balanced();
    }
}

static void collectionHandoff()
{
    auto owner = value(eVK_Object);
    auto o = static_cast<Object *>(owner.uValue.fObject);
    CUTF16String key;
    json_wconv(L"key", &key);
    o->properties[key] = value(eVK_Collection);
    auto c = static_cast<ShimCollection *>(ob_get_c(o, L"key"));
    assert(c && c->refs == 2);
    clear(owner);
    assert(collections.count(c) && c->refs == 1);
    PA_DisposeCollection(c);
    balanced();

    owner = value(eVK_Object);
    auto child = value(eVK_Object);
    ob_set_o(owner.uValue.fObject, L"child", child.uValue.fObject);
    // The setter consumes the caller's independent owner after the host copies it.
    child.fType = eVK_Undefined;
    auto col = value(eVK_Collection);
    ob_set_c(owner.uValue.fObject, L"collection", col.uValue.fCollection);
    col.fType = eVK_Undefined;
    clear(owner);
}

static void callbacks()
{
    methodName = expected;
    SERIAL::LISTENER_METHOD.setUTF16String(methodName.data(), methodName.size());
    for (auto kind : {eVK_Undefined, eVK_Unistring, eVK_Object, eVK_Collection, eVK_Blob}) {
        for (bool copied : {false, true}) {
            returnKind = kind;
            copyInput = copied;
            SERIAL::SERIAL_PATH = [[NSMutableArray alloc] init];
            SERIAL::SERIAL_DATA = [[NSMutableArray alloc] init];
            [SERIAL::SERIAL_PATH addObject:
                [NSString stringWithCharacters:expected.data() length:expected.size()]];
            [SERIAL::SERIAL_DATA addObject:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
            listenerLoopExecuteMethod();
            assert([SERIAL::SERIAL_PATH count] == 0);
            assert([SERIAL::SERIAL_DATA count] == 0);
            [SERIAL::SERIAL_PATH release];
            [SERIAL::SERIAL_DATA release];
        }
    }
}

static void arrays()
{
    PA_Variable ar = PA_CreateVariable(eVK_ArrayUnicode);
    PA_ResizeArray(&ar, 2);
    auto input = makeString(expected);
    PA_SetStringInArray(ar, 0, &input);
    auto borrowed = PA_GetStringInArray(ar, 0);
    assert(borrowed.fString == input.fString);
    auto independent = makeString(text(borrowed));
    if (!expected.empty()) assert(independent.fString != borrowed.fString);
    PA_SetStringInArray(ar, 1, &independent);
    auto replacement = makeString(CUTF16String(1, 'x'));
    PA_SetStringInArray(ar, 0, &replacement);
    for (int i = 0; i < 50; ++i) {
        auto churn = makeString(CUTF16String(128, 'z'));
        dispose(churn);
    }
    assert(text(PA_GetStringInArray(ar, 1)) == expected);
    auto rejected = makeString(expected);
    PA_SetStringInArray(ar, -1, &rejected);
    PA_SetStringInArray(ar, 3, &rejected);
    auto wrong = PA_CreateVariable(eVK_Undefined);
    PA_SetStringInArray(wrong, 0, &rejected);
    auto noData = ar;
    noData.uValue.fArray.fData = nullptr;
    PA_SetStringInArray(noData, 0, &rejected);
    PA_SetStringInArray(ar, 0, nullptr);
    assert(text(rejected) == expected);
    dispose(rejected);
    PA_ResizeArray(&ar, 0);
    PA_ClearVariable(&ar);
    balanced();

    ARRAY_TEXT wrapper;
    wrapper.appendUTF16String(expected.data(), expected.size());
    wrapper.appendUTF16String(expected.data(), expected.size());
    PA_Variable out = PA_CreateVariable(eVK_Undefined);
    BytePtr parameter[] = {reinterpret_cast<BytePtr>(&out)};
    wrapper.toParamAtIndex(parameter, 1);
    assert(text(PA_GetStringInArray(out, 0)) == expected);
    assert(text(PA_GetStringInArray(out, 1)) == expected);
    ARRAY_TEXT copied;
    copied.fromParamAtIndex(parameter, 1);
    wrapper.setSize(1);
    wrapper.toParamAtIndex(parameter, 1);
    CUTF16String saved;
    copied.copyUTF16StringAtIndex(&saved, 1);
    assert(saved == expected);
    PA_ClearVariable(&out);
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    gCall4D = engine;
    @autoreleasepool {
        const PA_Unichar ascii[] = {'p', 'o', 'r', 't', 0};
        const PA_Unichar bmp[] = {0x65e5, 0x672c, 0};
        const PA_Unichar supplementary[] = {'p', 0xd83d, 0xde80, 0};
        const char *utf8Fixtures[] = {"", "port", "\xe6\x97\xa5\xe6\x9c\xac",
                                     "p\xf0\x9f\x9a\x80"};
        for (bool emptyRepresentation : {false, true}) {
            nullEmpty = emptyRepresentation;
            size_t fixtureIndex = 0;
            for (auto fixture : {CUTF16String(), CUTF16String(ascii),
                                 CUTF16String(bmp), CUTF16String(supplementary)}) {
                expected = fixture;
                expectedUTF8 = CUTF8String(
                    reinterpret_cast<const uint8_t *>(utf8Fixtures[fixtureIndex++]));
                assert(utf8(expected) == expectedUTF8);
                std::string mode(argv[1]);
                if (mode == "setters") setters();
                else if (mode == "properties") properties();
                else if (mode == "collection") collectionHandoff();
                else if (mode == "arrays") arrays();
                else if (mode == "method" || mode == "command") {
                    methodBranch = mode == "method";
                    callbacks();
                } else abort();
                balanced();
            }
        }
    }
    printf("%s: exact content and ownership balance passed\n", argv[1]);
}
