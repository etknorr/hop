# Debian's /etc/zsh/zshrc runs a plain compinit, which stops at a prompt about insecure fpath dirs on CI runners; .zshrc runs its own.
skip_global_compinit=1
