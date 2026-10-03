Definitions:

- All sets are made up of "\N" characters, where `N` is a number between 0 and 255, including both ends, `ANY`.
- `|` is a union of the two sets
- `..` is a concatenation of the two sets
- Whitespace has no meaning.
- `&` is an intersection of the two sets
- `~` is a negation of the set
- `+` is one or more repetitions of the set
- `[a-b]` is a set of all bytes between the two specified bytes, including both `a` and `b`.
- `a{N}` where `N` is a number represents `N` repetitions of set `a`
- `(a)` allows for order of operations, first priority
- `$NAME` is an `ANY` variable where `NAME` is `[a-zA-Z]+`, and can be narrowed using operations.
 `NAME` can be used in the same scope, or definition origin, as a number representing the byte at the specified location, or the byte itself.
 Redefinitions (`$NAME`) do not change the value of prior usages of `NAME`.

- An intersection of a set with one or more repetitions (+) and a limited repetition set result in the a set with strings of length specified by the limited repetitions

Regular Expression Form:

What format is capable of being deserialized.

```terminaloutput
FORMAT = ANY_TYPE
ANY_TYPE = NIL | BOOLEAN | BUFFER | STRING | NUMBER | VECTOR | TABLE | USERDATA

NIL = "\0"

BOOLEAN = TRUE | FALSE
TRUE = "\1"
FALSE = "\2"

ANY = ["\0"-"\255"]

BUFFER = EMPTY_BUFFER
      | (BUFFER_BYTE_SIZE .. $BYTE .. ANY{BYTE})
      | (BUFFER_CHAR_SIZE .. $BYTE .. $CHAR .. ANY{CHAR * 2^8 + BYTE})
      | (BUFFER_TRYTE_SIZE .. $BYTE .. $CHAR .. $TRYTE .. ANY{TRYTE * 2^16 + CHAR * 2^8 + BYTE})
      | (BUFFER_INT_SIZE .. $BYTE .. $CHAR .. $TRYTE .. $INT .. ANY{INT * 2^24 + TRYTE * 2^16 + CHAR * 2^8 + BYTE})
EMPTY_BUFFER = "\3"
BUFFER_BYTE_SIZE = "\4"
BUFFER_CHAR_SIZE = "\5"
BUFFER_TRYTE_SIZE = "\6"
BUFFER_INT_SIZE = "\7"

STRING = EMPTY_STRING
      | (STRING_BYTE_SIZE .. $BYTE .. ANY{BYTE})
      | (STRING_CHAR_SIZE .. $BYTE .. $CHAR .. ANY{CHAR * 2^8 + BYTE})
      | (STRING_TRYTE_SIZE .. $BYTE .. $CHAR .. $TRYTE .. ANY{TRYTE * 2^16 + CHAR * 2^8 + BYTE})
      | (STRING_INT_SIZE .. $BYTE .. $CHAR .. $TRYTE .. $INT .. ANY{INT * 2^24 + TRYTE * 2^16 + CHAR * 2^8 + BYTE})
      | (($SIZE & SHORT_STRING) .. ANY{SIZE - 13})
EMPTY_STRING = "\8"
STRING_BYTE_SIZE = "\9"
STRING_CHAR_SIZE = "\10"
STRING_TRYTE_SIZE = "\11"
STRING_INT_SIZE = "\12"
SHORT_STRING = ["\13"-"\27"]

NUMBER = NUMBER_CONSTANTS
      | (BYTE .. ANY)
      | (CHAR .. ANY{2})
      | (TRYTE .. ANY{3})
      | (INT .. ANY{4})
      | (FLOAT .. ANY{4})
      | (DOUBLE .. ANY{8})
NUMBER_CONSTANTS = ZERO | ONE | NAN
ZERO = "\97"
ONE = "\98"
BYTE = "\99"
CHAR = "\100"
TRYTE = "\101"
INT = "\102"
FLOAT = "\103"
DOUBLE = "\104"
NAN = "\105"

VECTOR = VECTOR_CONSTANTS
      | (VECTOR_BYTE .. ANY{3})
      | (VECTOR_CHAR .. ANY{6})
      | (VECTOR_TRYTE .. ANY{9})
      | (VECTOR_FLOAT .. ANY{12})
      | (VECTOR_NUMBER .. NUMBER{3})
      | (VECTOR_SCALAR .. VECTOR_CONSTANTS .. NUMBER)
VECTOR_CONSTANTS = ["\142"-"\149"]
VECTOR_BYTE = "\150"
VECTOR_CHAR = "\151"
VECTOR_TRYTE = "\152"
VECTOR_FLOAT = "\153"
VECTOR_NUMBER = "\154"
VECTOR_SCALAR = "\155"

TABLE = EMPTY_TABLE
     | (DICT .. (KEY .. VALUE)+ .. TABLEEND)
     | (ARRAY .. ARRAY_VALUE+ .. TABLEEND)
     | (TABLESTART .. ARRAY_VALUE+ .. ARRAYEND .. (KEY .. VALUE)+ .. TABLEEND)
ARRAY_VALUE = VALUE & NIL
VALUE = ANY_TYPE & ~NIL & EXISTING_SEQUENCE
KEY = ANY_TYPE & ~INVALID_KEY & EXISTING_SEQUENCE
INVALID_KEY = NIL | NAN
      | (VECTOR_NUMBER .. (NUMBER{3} & NAN+))
      | (VECTOR_SCALAR .. VECTOR_CONSTANTS .. NAN)
EXISTING_SEQUENCE = EXISTING .. ANY{2}
EMPTY_TABLE = "\194"
TABLESTART = "\195"
EXISTING = "\196"
DICT = "\197"
ARRAY = "\198"
ARRAYEND = "\199"
TABLEEND = "\200"

USERDATA = UNSUPPORTED | CUSTOM .. ANY+
CUSTOM = "\202"
UNSUPPORTED = "\203"
```

### Supported Types

`nil`, `boolean`, `buffer`, `string`, `number`, `vector`, `table`, `userdata`

All other types are to be treated as `nil`.

### FAQ

**How are numbers stored?  Big-endian or little-endian.**

Numbers are stored in little-endian.

**Are strings compressed?**

No, strings and buffers are stored in their raw form, as sequences of bytes.

**What constitutes an array?**

An array is a list of elements from index 1 to n where there exist no gaps
 between the indeces 1 and n when incrementing the index by 1.

**What are vectors?**

Vectors are immutable storage mediums for three 32-bit floating point numbers
 `(x,y,z)`.

**How are cyclic tables stored?**

Values are recorded and any duplicate is fast pathed to avoid re-serializing and
 is compressed to 3 bytes (`196`).  Tables are recorded before serializing, so
 cyclic tables are stored as 3 byte references to prior serialized or currently
 serializing tables.

**What are the limitations to the duplicate value byte?**

The first 61,440 unique values serialized are finalized as duplicate values, excluding 
 `NaN` values or values that won't benefit from caching, values serializable in 1-2 bytes.  
 Values that can contain reference to other values, such as tables or userdata are
 always counted as unique values that can benefit from the duplicate value byte.
 Each usage of an above value will result in the above value stored in 3 bytes.  Since
 bytes are `0`-indexed, the value stored alongside the duplicate value byte (`196`)
 would be `UNIQUE_VALUE_POSITION - 1` where after each time a value is added, 
 `UNIQUE_VALUE_POSITION` is incremented, starting at 1.  Unique values immediately
 past 61,440 will continue as prior, however after reaching the 65,536th unique value,
 the `UNIQUE_VALUE_POSITION` is reset to 61,441 instead of incrementing by 1.  Such a pattern persists, and has drawbacks
 when backreferencing a unique value assumed to be stored as a duplicate value.

**How can I find the size of a table?**

The table size is not stored by default, see [extension support](../extension.md).

**Why are vectors stored in different formats?**

Vectors have multiple modes: scalar multiple, multi-set (byte, char, tryte), and set.  Scalar multiple vectors are multiples of the constant vectors, thus they can be stored in less bytes.  The intent behind multiple modes is primarily to produce smaller output sizes.  Vectors are basically numerical arrays of size 3, so two common cases (multi-set and set) were chosen to account for all cases and then special cases (scalar multiple) get a fast path with little cost.

## Design

| Tag(s)  | Cost     | Type       | Description                                 |
|---------|----------|------------|---------------------------------------------|
| 0       | 1        | `nil`      | The constant `nil` or unsupported types     |
| 1       | 1        | `boolean`  | The constant `true`                         |
| 2       | 1        | `boolean`  | The constant `false`                        |
| 3       | 1        | `buffer`   | An empty buffer                             |
| 4       | 2 + size | `buffer`   | A buffer with size < 2^8                    |
| 5       | 3 + size | `buffer`   | A buffer with size < 2^16                   |
| 6       | 4 + size | `buffer`   | A buffer with size < 2^24                   |
| 7       | 5 + size | `buffer`   | A buffer with size < 2^32                   |
| 8       | 1        | `string`   | The constant `""`                           |
| 9       | 2 + size | `string`   | A string with size < 2^8                    |
| 10      | 3 + size | `string`   | A string with size < 2^16                   |
| 11      | 4 + size | `string`   | A string with size < 2^24                   |
| 12      | 5 + size | `string`   | A string with size < 2^32                   |
| 13      | 2        | `string`   | A string of size 1                          |
| 14      | 3        | `string`   | A string of size 2                          |
| 15      | 4        | `string`   | A string of size 3                          |
| 16      | 5        | `string`   | A string of size 4                          |
| 17      | 6        | `string`   | A string of size 5                          |
| 18      | 7        | `string`   | A string of size 6                          |
| 19      | 8        | `string`   | A string of size 7                          |
| 20      | 9        | `string`   | A string of size 8                          |
| 21      | 10       | `string`   | A string of size 9                          |
| 22      | 11       | `string`   | A string of size 10                         |
| 23      | 12       | `string`   | A string of size 11                         |
| 24      | 13       | `string`   | A string of size 12                         |
| 25      | 14       | `string`   | A string of size 13                         |
| 26      | 15       | `string`   | A string of size 14                         |
| 27      | 16       | `string`   | A string of size 15                         |
| 28-96   | 0        | `string`   | **Unknown**                                 |
| 97      | 1        | `number`   | The constant `0`                            |
| 98      | 1        | `number`   | The constant `1`                            |
| 99      | 2        | `number`   | An integer between -2^7 and 2^7-1           |
| 100     | 3        | `number`   | An integer between -2^15 and 2^15-1         |
| 101     | 4        | `number`   | An integer between -2^23 and 2^23-1         |
| 102     | 5        | `number`   | An integer between -2^31 and 2^31-1         |
| 103     | 5        | `number`   | A 32-bit floating point                     |
| 104     | 9        | `number`   | A 64-bit floating point                     |
| 105     | 1        | `number`   | The constant `NaN` or `0 / 0`               |
| 106-141 | 0        | `number`   | **Unknown**                                 |
| 142     | 1        | `vector`   | The constant `(0,0,0)`                      |
| 143     | 1        | `vector`   | The constant `(1,1,1)`                      |
| 144     | 1        | `vector`   | The constant `(1,0,0)`                      |
| 145     | 1        | `vector`   | The constant `(0,1,0)`                      |
| 146     | 1        | `vector`   | The constant `(0,0,1)`                      |
| 147     | 1        | `vector`   | The constant `(1,1,0)`                      |
| 148     | 1        | `vector`   | The constant `(1,0,1)`                      |
| 149     | 1        | `vector`   | The constant `(0,1,1)`                      |
| 150     | 4        | `vector`   | A vector between -2^7 and 2^7-1 (all)       |
| 151     | 7        | `vector`   | A vector between -2^15 and 2^15-1 (all)     |
| 152     | 10       | `vector`   | A vector between -2^23 and 2^23-1 (all)     |
| 153     | 13       | `vector`   | A vector with 32-bit floating points        |
| 154     | 4-15     | `vector`   | A vector with different types               |
| 155     | 3-7      | `vector`   | A multiple of a constant vector             |
| 156-193 | 0        | `vector`   | **Unknown**                                 |
| 194     | 1        | `table`    | The constant `{}`                           |
| 195     | 3 + size | `table`    | A mixed table                               |
| 196     | 3        | `table`    | Duplicate value                             |
| 197     | 2 + size | `table`    | An array                                    |
| 198     | 2 + size | `table`    | A dictionary                                |
| 199     | 1        | `table`    | Array section terminator                    |
| 200     | 1        | `table`    | Table terminator                            |
| 201     | 1        | `table`    | **Unknown**                                 |
| 202     | 1 + size | `userdata` | Custom userdata                             |
| 203     | 1        | `userdata` | Represents all unsupported userdata         |
| 204-215 | 0        | `userdata` | **Unknown**                                 |
| 216-239 | 0        | `future`   | Reserved for new types or expansions        |
| 240-255 | 0        | `extend`   | Reserved for extenders                      |
