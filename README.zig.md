# Zig facade API

This is the typed facade reference. The `c` namespace exposes the complete translated C declarations, including IXA. Package consumption and build options are in `README.md`.

## Inputs and helpers

- `Atom` and `Stereo0D` are upstream C types. `Atom` fields are public; raw adjacency lists must keep `num_bonds`, `neighbor`, `bond_type`, and `bond_stereo` consistent. `connect` maintains them.
- `Molecule` borrows `atoms: []const Atom`, optional `stereo0d`, and `options: ?[:0]const u8`. The option string passes to InChI unchanged; null or empty means no options.
- `ExtendedMolecule` borrows polymer and V3000 data and takes mutable `atoms: []Atom`: `fromMolecule.extended` may rewrite `*` element names to `Zz`.
- `ImplicitHydrogens` has `ordinary`, `protium`, `deuterium`, and `tritium` counts; `.none` is zeroed and `.automatic` sets ordinary hydrogens to upstream's `-1` sentinel.
- `PolymerUnit`, `Polymer`, and `V3000` alias upstream input types. `AuxData` aliases upstream `InchiInpData`.
- Enums: `BondType` (`none`, `single`, `double`, `triple`, `altern`); `BondStereo2D` (`none`, `single_1up`, `single_1either`, `single_1down`, `single_2up`, `single_2either`, `single_2down`, `double_either`); `StereoType0D` (`none`, `double_bond`, `tetrahedral`, `allene`); and `StereoParity0D` (`none`, `odd`, `even`, `unknown`, `undefined`). Parity is relative to `Stereo0D.neighbor` order. `doubleBondStereo` builds a double-bond descriptor; construct an allene directly as `Stereo0D`.
- Constants mirror the translated header: `max_bonds_per_atom`, `element_symbol_len`, `error_buffer_len`, `no_atom`, `key_buffer_len`, and `hash_buffer_len`.

| Helper | Signature and contract |
|---|---|
| `atom` | `atom(symbol: []const u8, hydrogens: ImplicitHydrogens) Error!Atom`; returns a zeroed atom with the supplied symbol and hydrogen counts. |
| `connect` | `connect(atoms: []Atom, first: usize, second: usize, kind: BondType, stereo2d: BondStereo2D) Error!void`; adds both directions or neither. |
| `tetrahedralStereo` | `tetrahedralStereo(central: i16, neighbours: [4]i16, parity: StereoParity0D) Stereo0D`; preserves the given neighbour order. |
| `doubleBondStereo` | `doubleBondStereo(x: i16, a: i16, b: i16, y: i16, parity: StereoParity0D) Stereo0D`; builds a stereogenic double bond. |

## Conversion and validation

All option parameters are `?[:0]const u8`; text inputs are NUL-terminated slices.

| API | Result |
|---|---|
| `fromMolecule.standard(molecule: Molecule)` | `Error!Output`; produces a standard identifier. |
| `fromMolecule.full(molecule: Molecule)` | `Error!Output`; honours options that may produce a non-standard identifier. |
| `fromMolecule.extended(molecule: ExtendedMolecule)` | `Error!Output`; accepts polymer and V3000 input; may rewrite wildcard atom names. |
| `fromIdentifier.standard(text, options)` | `Error!Structure`; refuses non-standard identifiers. |
| `fromIdentifier.full(text, options)` | `Error!Structure`; accepts standard or non-standard identifiers. |
| `fromIdentifier.extended(text, options)` | `Error!ExtendedStructure`; also rebuilds polymer and V3000 blocks. |
| `fromIdentifier.converted(text, options)` | `Error!Output`; regenerates an identifier from an identifier. |
| `fromAuxInfo.standard(aux_info, options, do_not_add_h)` | `Error!AuxStructure`; reads standard AuxInfo. |
| `fromAuxInfo.full(aux_info, options, do_not_add_h, distinguish_unknown_undefined)` | `Error!AuxStructure`; selects how unknown and undefined stereo are read. |
| `fromMolfile(text, options)` | `Error!MolfileOutput`; generates an identifier from molfile text. |
| `key(text, hashes: Hashes)` | `KeyError!KeyResult`; `Hashes.first` and `.second` independently request extension hashes (both default false). |
| `standardKey(text)` | `KeyError!KeyResult`; accepts standard identifiers and computes no extension hashes. |
| `checkIdentifier(text, strict: bool)` | `IdentifierVerdict`; strict mode regenerates the identifier and requires an exact match. |
| `checkKey(text)` | `KeyVerdict`. |

`Error` covers local validation: `ElementSymbolTooLong`, `AtomIndexOutOfRange`, `TooManyNeighbors`, and `TooManyAtoms`. C conversion outcomes are status values, not Zig errors.

## Results and ownership

| Result | Fields and accessors |
|---|---|
| `Output` | `status`, `origin`; `identifier`, `auxInfo`, `message`, `log`, `isWarning`, `deinit`. |
| `MolfileOutput` | `status`; `identifier`, `auxInfo`, `message`, `log`, `isWarning`, `deinit`. |
| `Structure` | `status`, `origin`; `atoms`, `stereo0d`, `message`, `log`, `warnings`, `isWarning`, `deinit`. |
| `ExtendedStructure` | Structure accessors plus `polymer` and `v3000`; `deinit` releases all blocks. |
| `AuxStructure` | `status`, `origin`; `atoms`, `stereo0d`, `chiralMark`, `parseMessage`, `molecule`, `deinit`. |
| `KeyResult` | `keyText`, `firstHash`, `secondHash`; fixed-size buffers live in the value. |

`Output`, `MolfileOutput`, `Structure`, `ExtendedStructure`, and `AuxStructure` own upstream allocations. Call `deinit` exactly once, including when status reports refusal; returned slices are borrowed and expire at release. `KeyResult` needs no release and may be copied.

`Status` is non-exhaustive: `.no_data`, `.okay`, `.warning`, `.rejected`, `.fatal`, `.unknown`, `.busy`, or an unnamed code. A warning can still carry an identifier. `MolfileStatus` has a separate non-exhaustive code set: `.okay`, `.warning`, `.no_data`, `.rejected`, `.structure_failed`, and `.generation_failed`; the pinned molfile producer reports read and generation failures as `.rejected`. `Origin` is `.standard` or `.non_standard` and selects the release function.

`IdentifierVerdict` is `.standard`, `.non_standard`, `.beta`, `.invalid_prefix`, `.invalid_version`, `.invalid_layout`, `.conversion_failed`, or an unnamed code. `KeyVerdict` preserves native values: `.standard = 0`, `.non_standard = -1`, `.invalid_length = 1`, `.invalid_layout = 2`, `.invalid_version = 3`, or an unnamed code. `KeyError` is `UnknownFailure`, `InvalidInchiPrefix`, `NotEnoughMemory`, `InvalidInchi`, or `InvalidStdInchi`. `Warnings` is the raw `[2][2]c_ulong` difference-flag array.

## Runtime-loading API

`runtime_loaded: bool`, `LoadSource`, `LoadError`, `load(source: LoadSource) LoadError!void`, and `loadedSource() ?LoadSource` describe the module's runtime-loading state. `LoadSource` is `.path` or `.system`; requests are explicit, and paths must be absolute. Calling `load` in a linked build panics. `LoadError` is `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, or `ReentrantLoad`.

`c` is the escape hatch for declarations without typed wrappers. It retains upstream's contracts; in particular, `GetINCHIEx` writes through its atom array.