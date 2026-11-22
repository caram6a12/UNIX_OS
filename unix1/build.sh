#!/bin/sh
set -u

die() {
    echo "Ошибка: $1" >&2
    exit "${2:-6}"
}

[ $# -eq 1 ] || { echo "Использование: $0 <исходный_файл>" >&2; exit 1; }
srcfile=$1
[ -f "$srcfile" ] && [ -r "$srcfile" ] || die "файл '$srcfile' не найден или недоступен" 2

case "$srcfile" in
    *.c|*.h)                 kind=c   ;;
    *.cc|*.cpp|*.cxx|*.hpp)  kind=cpp ;;
    *.tex)                   kind=tex ;;
    *) die "неизвестный тип '$srcfile'" 3 ;;
esac

pick() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 && { echo "$c"; return 0; }
    done
    return 1
}
case "$kind" in
    c)   tool=$(pick cc gcc clang)       || die "нет C-компилятора (cc/gcc/clang)" 3 ;;
    cpp) tool=$(pick c++ g++ clang++)    || die "нет C++ компилятора (c++/g++/clang++)" 3 ;;
    tex) tool=$(pick pdflatex latex)     || die "нет TeX-движка (pdflatex/latex)" 3 ;;
esac

extract_output() {
    local file=$1 k=$2 line
    case "$k" in
        c|cpp)
            line=$(sed -n 's|^[[:space:]]*//[[:space:]]*Output:[[:space:]]*\([^[:space:]]*\).*$|\1|p' "$file" | sed -n 1p)
            [ -n "$line" ] && { echo "$line"; return 0; }
            line=$(sed -n '/\/\*/,/\*\//{
                s|.*Output:[[:space:]]*\([^[:space:]*]*\).*|\1|p
            }' "$file" | sed -n 1p)
            [ -n "$line" ] && { echo "$line"; return 0; }
            return 1
            ;;
        tex)
            line=$(sed -n 's|^[[:space:]]*%[[:space:]]*Output:[[:space:]]*\([^[:space:]]*\).*$|\1|p' "$file" | sed -n 1p)
            [ -n "$line" ] && { echo "$line"; return 0; }
            return 1
            ;;
    esac
}
output_name=$(extract_output "$srcfile" "$kind") \
    || die "не найден комментарий 'Output: <имя>' в '$srcfile'" 4

case "$output_name" in
    /*) die "недопустимое имя результата '$output_name' (абсолютный путь)" 4 ;;
    */*) die "недопустимое имя результата '$output_name' (содержит '/')" 4 ;;
    ..|../*|*/..|*/../*) die "недопустимое имя результата '$output_name'" 4 ;;
    '') die "пустое имя результата в комментарии 'Output:'" 4 ;;
esac

tmpdir=$(mktemp -d) || die "не удалось создать временный каталог" 6

exit_handler() {
    local rc=$?
    trap - EXIT HUP INT QUIT PIPE TERM
    rm -rf -- "$tmpdir" 2>/dev/null || true
    exit "$rc"
}
trap exit_handler EXIT HUP INT QUIT PIPE TERM

srcname=$(basename "$srcfile")
cp "$srcfile" "$tmpdir/$srcname" || die "не удалось скопировать исходник" 6

olddir=$(pwd)
cd "$tmpdir" || die "не удалось перейти во временный каталог" 6

case "$kind" in
    tex)
        base=${srcname%.*}
        "$tool" -interaction=nonstopmode "$srcname" >/dev/null 2>&1
        build_ok=$?
        ;;
    *)
        "$tool" -o "$output_name" "$srcname" >/dev/null 2>&1
        build_ok=$?
        ;;
esac

cd "$olddir" || die "не удалось вернуться в исходный каталог" 6
[ "$build_ok" -eq 0 ] || die "сборка '$srcfile' не удалась" 5

srcdir=$(dirname "$srcfile")
dest="$srcdir/$output_name"

if [ "$kind" = tex ]; then
    case "$output_name" in
        *.pdf|*.dvi) out_ext=${output_name##*.} ;;
        *)           out_ext=pdf ;;
    esac
    produced="$tmpdir/$base.$out_ext"
    [ -f "$produced" ] || die "после компиляции TeX не найден файл '$base.$out_ext'" 6
    case "$output_name" in
        *.pdf|*.dvi) cp "$produced" "$dest" || die "не удалось скопировать результат" 6 ;;
        *)           cp "$produced" "$dest.$out_ext" || die "не удалось скопировать результат" 6
                     dest="$dest.$out_ext" ;;
    esac
else
    [ -f "$tmpdir/$output_name" ] || die "не найден скомпилированный файл '$output_name'" 6
    cp "$tmpdir/$output_name" "$dest" || die "не удалось скопировать результат" 6
fi

echo "Готово: '$dest'"