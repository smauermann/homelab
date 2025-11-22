# Project rules

- keep it simple, simple is better than complex and more robust
- if you don't know what chart values there are, use `helm show values repo/chartname --version 1.2.3`
- use semantic commits
- after every logical block of work, commit your changes
- some secrets are encrypted with SOPS; never commit decrypted files
