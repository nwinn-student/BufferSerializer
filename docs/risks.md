# Risks

This document outlines potential risks associated with the serialization and
 deserialization of data structures, particularly in the context of the
 BufferSerializer library. It is crucial to understand these risks to mitigate
 potential vulnerabilities in applications that utilize these techniques.

### Back References

The `equal_existing` byte is defined as a way to store a prior unique
 value in a compressed form.  That is, all unique values are input into a
 cache and numbered, should the value appear again, the number associated
 with the value in the cache will be stored.

An attacker could modify the number attached to the `equal_existing`
 byte to reference a prior unique value.  The resulting behavior is that
 the attacker could cause an error or freeze to occur when handling the
 deserialized form.

The recommended solution is to use standard
 security practices when handling the data.

#### Userdata Custom Approach

Requires careful handling to ensure custom serialization and
 deserialization functions are compatible across versions.  The buffer containing
 the serialization data could be modified illegally, the userdata
 could also be modified.

#### Limitations

- Although cyclic tables<sup>[1]</sup> are supported, large datasets with
  distant<sup>[2]</sup> cyclic tables will fatally error.  Although possible,
  the solution would be too costly.

<sub>[1]: Tables that point to other tables that at some point, point back to
the initial pointing table.</sub>

<sub>[2]: Large datasets are datasets with at least 61_440 unique values,
including dictionary keys and excluding constants.  Distant cyclic tables
are cyclic tables that are at least 4_096 unique values apart.</sub>