## Migration

When migrating, the following steps are used.

1. Pass the serialized data into the deserializer, retrieving the original data
2. Pass the original data into the serializer for the desired format or version.

For stored data:

In order to know which deserializer to use, it is recommended to consistently store
 the format's version outside of the data itself.  Failing to do so will result in
 illformed data.  Storing the version inside the data itself fails to account for
 incompatible data format changes.

For network data, or other data that is in-transit and does not require storing,
 there is no need to migrate between format versions.  Merely ensuring that both
 ends use the same format version is enough.

## Reducing output size

1. Reformat the dataset to produce a minimal output size in
 JSON.
   - Easier to iterate since the output is readable.
   - Reductions are often reflected in BufferSerializer.

2. Convert strings that can be expressed as unions into numbers, identifiers.
   - A `Greeting` union would be "Hello" -> 1, "Hey" -> 2, "What's up" -> 3, etc.
   - **Use with caution.** Haphazard changes to id-value pairs causes migration
 concerns.  See [patch for pairs](https://github.com/nwinn-student/luau-buffer-serialize/discussions/36).

3. Identify whether there are arrays in the dataset with gaps worth filling
 with nil bytes, functions and threads can be used to represent `nil`.
   - In `{ 1, 2, _, 4, 5 }`, where `_` denotes a gap, adding a placeholder function
 will reduce the output size from 14 to 10 bytes.
   - Determining worth requires looking at the output size as combinations of gaps
 are filled.

4. The more known about the dataset, the smaller the output size can be.
   - Knowledge of a dataset's schema (or shape) can be used to morph the dataset
 into a cheaper form (using 3.).
   - Numbers can be compressed when precision is not important.  Ex: A random number (0-1) can be stored as a byte when we only care about nearest 0.005.

## Avoid using backwards references

A backwards reference is a structural value, of type `table` or `userdata`, that is to be serialized that has been serialized **prior**.  There are two types of backwards references, those that are horizontal from a structural standpoint and those that are vertical.  A horizontal reference is a reference that does not contain a reference to itself within its structure, whereas a vertiical reference contains a reference to itself within its structure.  Horizontal references are used to reduce output size, however may be incorrectly assumed to retain the equality relationship upon deserialization.  The values will not have a guaranteed equivalence in their contents, as their identities may differ.  Vertical references should **not** be used, as they may cause an infinite loop.

The references must be utilized in such a way as to ensure that the distance between the initial usage of the value and the reference is less than 4096 unique values.  The aforementioned is a requirement for vertical references.  For horizontal references however, it is only a requirement when the equality relationship must be retained upon deserialization.
