# Native string ownership audit

Baseline: `1d6f48b0b097c72bbd1f0b352d395d08d1832dab`.
Guidance: `miyako/skills` native-plugin skill at merged PRs 69/71
(`e6b492fcb81e5e1a7f7db723594b420e63bf6eb9`).

## Inventory and reachability

| Surface | Evidence and scope |
|---|---|
| Commands | Source `manifest.json` and bundled `test/Plugins/Serial.bundle/Contents/Resources/manifest.json` match: Get available ports, Open path, Close path, Send data. Dispatcher cases 1-4 match their order. Scalar text, BLOB, object and collection parameters/results; no text-array command declaration. |
| Live native sources | Xcode compiles `4DPlugin-Serial.cpp` as Objective-C++, `support/4DPlugin-JSON.cpp`, `C_TEXT.cpp`, `C_LONGINT.cpp`, and `4DPluginAPI.c`. Both callback branches are reachable: method ID found, or Execute formula command 1007 fallback. |
| Live helpers | Port metadata uses string/bool/number setters; Open path uses property text/bool/number getters. `C_TEXT` copies input into its own C++ UTF-16 storage; its parameter/return content setters do not transfer that storage. `C_LONGINT` owns no strings. |
| Compiled dormant helpers | Other JSON string setter overloads, picture/object/collection/integer/null setters, collection getter and stringify are compiled but not all called by this plugin. Successful reference handoffs remain unchanged. Stringify already copies text and clears both normal and unexpected returned kinds. |
| Tracked, not compiled | `ARRAY_TEXT` and `C_BLOB` are absent from Xcode's sources phase and command reachability. Array input copies descriptors' contents; output creates independent strings and transfers each without immediate disposal. Normal/rejected array SDK contracts and normal wrapper roundtrips are regression controls, not evidence of a live text-array crash. |
| Windows project | Lists SDK and plugin source, but omits JSON/C_TEXT implementations; plugin unconditionally requires Objective-C/Cocoa/ORSSerialPort. This audit does not certify the stale Windows project or committed Windows binaries. |
| Exclusions | ORSSerialPort sources/headers/static library, JsonCpp, committed plugin binaries and test database/user data were not modified or executed. No first-party CPicture, C_POINTER, charset-conversion helper, application-path or picture-data consumer exists here. |

## Bundled SDK contracts

`4D Plugin API/4DPluginAPI.c` is unchanged. Its `rev : v14` comment is a
header revision, not a verified upstream SDK release identity.
Git blob: `62f745e91d81ef2c3c901c656ea8e175d3b173e8`.
SHA-256: `5bac571c5c4cafd280fa7f23d775458a23701287e8735be27d4a2190002f4e3f`.

All line references below are to the baseline SDK:

* `PA_CreateVariable` (3920-4060) creates an empty owned string for
  `eVK_Unistring` and a zero-size handle for `eVK_Blob`.
  `PA_SetStringVariable` (4254-4259) shallow-overwrites the descriptor.
  `PA_SetBlobVariable` (4262-4268) similarly overwrites the handle.
* `PA_SetUnistring` (289-299) forwards the current descriptor and
  null-terminated UTF-16 content to `EX_SET_UNISTRING`, then stores the updated
  descriptor. The engine-boundary fixture models content replacement with
  disposal of the previous allocation, including allocated and null empties.
* `PA_GetStringInArray` (4738-4755) returns a borrowed descriptor.
  `PA_SetStringInArray` (4933-4947) disposes the old element and shallow-transfers
  its input only for Unicode arrays with non-null data, non-null input and
  index 0 through the current count. Rejection leaves caller ownership intact.
* `PA_ExecuteMethodByID` (5710-5748) copies descriptors into a temporary handle,
  retrieves the returned owning variable, and disposes only the temporary
  handle. `PA_ExecuteCommandByID` (5778-5810) passes argument pointers and a
  separate result destination. Neither clears the returned owner for the caller.
* `PA_GetObjectProperty` (637-651) supplies a separate local variable to
  `EX_GET_OBJ_VALUE`. The synthetic host supplies an owning copy, not a borrowed
  property descriptor. Getters copy/read its payload before clearing it;
  `ob_get_c` transfers a successful collection owner to its caller instead.
* `PA_GetStringVariable` (4105-4119) forwards to `EX_VARIABLE_TO_STRING`;
  the boundary fixture returns a view into the owning variable for these
  text-valued calls. `PA_ClearVariable` (4401-4409) delegates cleanup to the
  engine. Object/collection property assignment is modeled as a retained/copied
  host value, so clearing the temporary preserves the property.

Engine allocation/reference behavior is explicitly modeled at these boundaries;
the SDK forwarding itself is executed, not reimplemented. This is not a test of
an installed 4D engine's implementation.

## Fixes

Four JSON string setters and the callback command-name argument now replace
content in the initially owned string instead of losing its empty allocation.
Both callback BLOB arguments start Undefined before the BLOB setter allocates
their payload. Both callback branches clear independent owning return values,
while retaining the existing cleanup of independently owned synchronous arguments.
Property text/bool/number getters clear their returned temporary after reading;
the collection getter clears only mismatches and preserves successful handoff.
No SDK or third-party source is changed.

## Regressions and limits

Run on macOS with Xcode command-line tools:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_ownership.py
SERIAL_OWNERSHIP_REF=1d6f48b0b097c72bbd1f0b352d395d08d1832dab \
  PYTHONDONTWRITEBYTECODE=1 python3 tests/test_ownership.py
```

The second command must fail: it materializes immutable baseline native
sources/headers with `git show`, then compiles those against the same current
harness. The final harness fails four baseline groups (setters, properties,
method callback, command callback), with explicit leaked string/handle/reference
counts. Array and collection-handoff controls pass on both revisions.
All six groups pass with the fix.

The harness compiles the full, unchanged SDK, actual full plugin/JSON source,
and actual C_TEXT/ARRAY_TEXT implementations with ASan and UBSan. It checks exact
ASCII, Japanese BMP, supplementary surrogate-pair and empty content and lengths,
explicit UTF-8 bytes, both empty-string representations, property mismatches
(text/object/collection included), missing keys, repeated callbacks with
Undefined/text/object/collection/BLOB returns and independent copies of input,
balanced string/handle allocations and object/collection references, independent
array transfers, borrowed-input copies, replacement after allocator churn,
shrink/clear, and rejected type/index/null-data/null-input array setters.

LeakSanitizer is disabled on macOS; SDK resource accounting remains mandatory
and fatal on imbalance. The legacy SDK needs `-Wno-int-conversion` when compiled
as C with current Clang because an existing integer is initialized with NULL.
The source's existing ORSSerialPort `existingPortWithPath:` declaration warnings
remain visible; no serial library is linked. Inert test classes abort if device
lookup or manager discovery is reached.

Only a temporary unsigned executable is built. No Xcode target, Deployment
configuration, release workflow, signing, notarization, packaging, uploads,
tag creation, physical ports or test database is used. CI runs only this
synthetic regression on macOS. No actual 4D host, Windows execution, async
redesign, callback-retention certification, or allocation-failure certification
is claimed. In particular, SDK array resize updates its count even if growth
fails; dormant wrapper allocation/resize failure handling remains deferred
rather than inferred safe from normal-array tests.
