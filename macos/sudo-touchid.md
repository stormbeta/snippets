# Enabling TouchID for sudo

Add the following line to `/etc/pam.d/sudo`:

```
auth       sufficient     pam_tid.so
```
