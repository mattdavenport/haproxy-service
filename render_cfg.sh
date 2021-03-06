#!/bin/bash
#
# Renders a foo.cfg.tpl file into foo.cfg
# Uses DNS RR resolution to render a line for each resolved host.
#
# $ render_cfg.sh <hostname> </path/to/haproxy.cfg.tpl>
#
service=$1
template=$2
oldfile=/tmp/cfg.$service
tmpfile=$(mktemp -t cfg.$service.XXXXXXX)
nslookup $service 2>/dev/null | gawk '/Address /{print $3}' | sort | paste -sd ',' > $tmpfile

# Check for fatal errors
if ! [ -f $template ]; then
  rm $tmpfile
  echo "Template file $template does not exist."
  exit 1
fi
if [ $(wc -c $tmpfile | gawk '{print $1}') -eq 0 ]; then
  rm $tmpfile
  echo "Unable to resolve addresses for $service "
  exit 1
fi

# Check if IP addresses for service changed
if test -f $oldfile && cmp -s $oldfile $tmpfile; then
  rm $tmpfile
  exit 2
fi

# Remove oldfile to prevent tmp file accumulation
if [ -f $oldfile ]; then
  rm $oldfile
fi

prefix=node
IFS=',' read -ra ips < $tmpfile
tmptpl=$(mktemp -t tpl.XXXXXXX)
tmptpl2=$(mktemp -t tpl.XXXXXXX)
cp $template $tmptpl
index=0
while true; do
  pattern=$(sed -n '/^\s*{{HOSTS}}$/,/^\s*{{\/HOSTS}}$/{//!p}' $tmptpl | head -n 1)
  #pattern='server ${service}${num} ${ip}:3306 check'
  [ -n "$pattern" ] || break
  gawk "BEGIN{a=0} /{{HOSTS}}/&&a==0 {f=1} !f; /{{\\/HOSTS}}/&&a==0 {print \"\${HOSTS$index}\"; f=0; a++}" $tmptpl > $tmptpl2
  HOSTS="";SEP=""
  for ip in "${ips[@]}"; do
    num=${ip##*.}
    host=$(eval "echo \"$pattern\"")
    HOSTS=$(printf "$HOSTS$SEP$host")
    SEP=$'\n'
  done
  eval "HOSTS$index=\"$(printf "$HOSTS")\""
  index=$(($index + 1))
  cp $tmptpl2 $tmptpl
done
eval "echo \"$(cat $tmptpl2)\"" > $tmptpl
mv $tmptpl ${template%.tpl}
mv $tmpfile $oldfile
rm $tmptpl2

# 0 means config was updated
exit 0
