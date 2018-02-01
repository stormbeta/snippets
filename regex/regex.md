# Regex patterns

## IPv4 address matcher

Matches exactly four numbers in the 0-255 range separated by periods.

```
(0|1[0-9]{1,2}|2[0-4][0-9]|25[0-5])(\.(0|1[0-9]{1,2}|2[0-4][0-9]|25[0-5])){3}
```

Explanation:

Match one of:
  - 0
  - 100-199
  - 200-249
  - 250-255

Match one of:
  - .0
  - .100-199
  - .200-249
  - .250-255
  Repeat thrice
