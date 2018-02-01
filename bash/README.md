# Bash-isms

Useful bits of bash that don't make sense to put in my bashrc files

## User prompt

```
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "doing the thing!"
fi
```

# Mac-specific

## auto-run file

```
fswatch FILE | xargs -n1 -I{} COMMAND {}
```

