---
summary: Prevent unaffiliated MUC participants from sending PMs
---

# Introduction

This module prevents unaffiliated users from sending private messages in
chat rooms, unless someone with an affiliation (member, admin etc)
messages them first.

# Configuration

The module doesn't have any options, just load it onto a MUC component.

``` lua
Component "muc"
modules_enabled = {
    "muc_block_pm";
}
```

# Compatibility

    Branch State
  -------- -----------------
       0.9 Works
      0.10 Should work
     trunk *Does not work*
