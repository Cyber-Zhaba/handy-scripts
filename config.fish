if command -q goenv
    set -x GOENV_ROOT $HOME/.goenv
    set -x PATH $GOENV_ROOT/bin $PATH
    status is-interactive; and source (goenv init -|psub)
    set -x GOENV_AUTOMATICALLY_DETECT_VERSION 1
end

if command -q eza
    alias ls 'eza -lh --group-directories-first --icons=auto'
    alias lsa 'ls -a'
    alias lt 'eza --tree --level=2 --long --icons --git'
    alias lta 'lt -a'
end

if command -q fzf
    alias ff "fzf --preview 'bat --style=numbers --color=always {}'"
end

if command -q zoxide
    zoxide init fish | source
end

function open --wraps=xdg-open
    xdg-open $argv >/dev/null 2>&1 &
end

alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'

if command -q amv
    alias mv "amv -g"
    alias cp "acp -g"
end

# opencode
fish_add_path /home/arseny/.opencode/bin
