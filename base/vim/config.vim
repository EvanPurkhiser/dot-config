set nocompatible

" Follow XDG directory specifications
let $MYVIMRC="$XDG_CONFIG_HOME/vim/vimrc"
set directory=$XDG_CACHE_HOME/vim
set viminfo+=n$XDG_CACHE_HOME/viminfo
set runtimepath=$XDG_CONFIG_HOME/vim,$XDG_CONFIG_HOME/vim/after,$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after,$XDG_CONFIG_HOME/vim/bundle/vundle

runtime config/vundles.vim
runtime config/general.vim
runtime config/mapping.vim
