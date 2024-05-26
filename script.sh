calc(){ awk "BEGIN { print "$*" }"; }

xvals=(8 16 16 32 32)
yvals=(8 8 16 16 32)

for idx in $(seq 0 4); do
    x="${xvals[idx]}"
    y="${yvals[idx]}"
    # echo "${x} ${y}"
    echo -n "\\hline ${x} x ${y}"
    for depth in $(seq 1 10); do
        a=$(./pruning -d "${depth}" -x ${x} -y ${y} -t)
        b=$(./pruning -d "${depth}" -x ${x} -y ${y})
        c=$(calc ${b}/${a})
        val=$(printf "%.3f" ${c})
        echo -n " & ${val}"
    done
    echo " \\\\"
done
