#!/bin/bash
# If you like my scripts, please donate via PayPal to epascual@gmail.com
#
# Script was written to check Pi-KVM's webui are either up or down
# ... and create/update a centralized Pi-KVM status website
###
# Pre-requisites:
# 1.  Run on linux webserver using document-root as /var/www/html (recommend pihole server)
# 2.  User running this has to have sudo access
# 3.  Sample crontab entry is as follows:
#     # pi-kvm website status updater (every 5 minutes)
#     */5 * * * *  /home/<userwithsudoaccess>/webui-chk.sh
#
# Was requested to check latest kvmd version and report which systems are running older software
# ... Requires ssh pubkey authentication, as per below
# 4.  In order to check for kvmd/ustreamer, contents of the user's .ssh/id_rsa.pub file
#     ... must be in pikvm:/root/.ssh/authorized_keys file for this to work
###
#
PIKVMS="pikvm pzkvm"   # Put your pi-kvm hostnames here

show_help() {
  echo "usage:  $0 [domain.local]               "
  exit 1
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
elif [[ "$1" != "" ]]; then
  DOMAIN="$1"
fi

PIKVMSITE="/var/www/html/pikvm.html"
if [ ! -e $PIKVMSITE ]; then
  sudo touch $PIKVMSITE
  sudo chmod ugo+w $PIKVMSITE
fi
# Clear out the website first
true > $PIKVMSITE

totalhosts=$( echo $PIKVMS | wc -w )

cat << BEGIN_HTML >> $PIKVMSITE
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><strong style="color: blue;">Last checked on $(date) which Pi-KVM webui are available.</strong></head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<TITLE>Pi-KVM Status Website by srepac</TITLE>
<body style="background-color:darkgray;">
<!body style="background-color:#789abc;">
<style type="text/css">
.tg  {border-collapse:collapse;border-color:#9ABAD9;border-spacing:0;margin:0px auto;}
.tg td{background-color:#EBF5FF;border-color:#9ABAD9;border-style:solid;border-width:1px;color:#444;
  font-family:Arial, sans-serif;font-size:14px;overflow:hidden;padding:10px 5px;word-break:normal;}
.tg th{background-color:#409cff;border-color:#9ABAD9;border-style:solid;border-width:1px;color:#fff;
  font-family:Arial, sans-serif;font-size:14px;font-weight:normal;overflow:hidden;padding:10px 5px;word-break:normal;}
.tg .tg-phtq{background-color:#D2E4FC;border-color:inherit;text-align:left;vertical-align:top}
.tg .tg-j1i3{border-color:inherit;position:-webkit-sticky;position:sticky;text-align:left;top:-1px;vertical-align:top;
  will-change:transform}
.tg .tg-0j1v{background-color:#D2E4FC;border-color:inherit;font-style:italic;text-align:left;vertical-align:top}
.tg .tg-0pky{border-color:inherit;text-align:left;vertical-align:top}
.tg .tg-f8tv{border-color:inherit;font-style:italic;text-align:left;vertical-align:top}
.tg-sort-header::-moz-selection{background:0 0}
.tg-sort-header::selection{background:0 0}.tg-sort-header{cursor:pointer}
.tg-sort-header:after{content:'';float:right;margin-top:7px;border-width:0 5px 5px;border-style:solid;
  border-color:#404040 transparent;visibility:hidden}
.tg-sort-header:hover:after{visibility:visible}
.tg-sort-asc:after,.tg-sort-asc:hover:after,.tg-sort-desc:after{visibility:visible;opacity:.4}
.tg-sort-desc:after{border-bottom:none;border-width:5px 5px 0}@media screen and (max-width: 767px) {.tg {width: auto !important;}.tg col {width: auto !important;}.tg-wrap {overflow-x: auto;-webkit-overflow-scrolling: touch;margin: auto 0px;}}</style>
<div class="tg-wrap"><table id="tg-VN0Hn" class="tg">
<thead>
  <tr>
    <th class="tg-j1i3"><span style="font-weight:bold">Pi-KVM URL</span></th>
    <th class="tg-j1i3"><span style="font-weight:bold">Website Status - kvmd/ustreamer version</span></th>
  </tr>
</thead>
<tbody>
BEGIN_HTML

# Check for the latest kvmd version in github
LATESTKVMD="/tmp/kvmd.version"; /bin/rm -f $LATESTKVMD
wget -O $LATESTKVMD https://github.com/pikvm/kvmd/raw/master/kvmd/__init__.py 2> /dev/null > /dev/null
#KVMDNEW=$( grep __version__ $LATESTKVMD | awk '{print $NF}' | sed 's/"//g' )
KVMDNEW=$( grep __version__ $LATESTKVMD | awk -F\" '{print $2}')

count=0; upgrade=0; unknown=0
for site in $PIKVMS; do
  if [[ "$DOMAIN" == "" ]]; then
    SITE="$site"
  else
    SITE="$site.$DOMAIN"
  fi
  # Get kvmd/ustreamer version from current Pi-KVM host
  PACMANQ="/tmp/pacmanquery.$site"; /bin/rm -f $PACMANQ
  ssh root@$SITE pacman -Q 2> /dev/null > $PACMANQ
  #KVMD=$( grep kvmd-platform $PACMANQ | sed -e 's/-[1-9]//g' -e 's/kvmd-platform-//g' )
  KVMD=$( grep kvmd-platform $PACMANQ | sed -e 's/-[1-9]//g' )
  KVMDVER=$( echo $KVMD | awk '{print $2}' )
  USTREAMER=$( grep ustreamer' ' $PACMANQ | sed 's/-[1-9]//g' )

  if [[ "$KVMD" == "" ]]; then
    KVMD="UNKNOWN VERSIONS"
    USTREAMER="ssh pubkey missing or host offline"
    UPDATE="*** fix required ***"
    let unknown=$unknown+1
  elif [[ "$KVMDVER" != "$KVMDNEW" ]]; then
    let upgrade=$upgrade+1
    UPDATE=" *** update available ***"
  else # pi-kvm is running latest kvmd version
    UPDATE=""
  fi

  # Get website status (200 is OK = UP, otherwise DOWN)
  STATUS=$( wget -S --spider --no-check-certificate https://$SITE 2>&1 | egrep -w '200' )
  if [[ "$STATUS" == "" ]]; then
    echo "   <tr><td class=\"tg-phtq\"><a href=\"https://$SITE\" target=\"_blank\">https://$SITE</a></td><td class=\"tg-0j1v\"><span style=\"font-weight:bold\"><span style=\"color: red\">DOWN</span></span> - $KVMD / $USTREAMER  $UPDATE</td></tr><p>" >> $PIKVMSITE
    printf "    https://%-30s\t%-4s\n" $SITE "down"
  else
    echo "   <tr><td class=\"tg-0pky\"><a href=\"https://$SITE\" target=\"_blank\">https://$SITE</a></td><td class=\"tg-f8tv\"><span style=\"font-weight:bold\"><span style=\"color: green\">UP</span></span> - $KVMD / $USTREAMER  $UPDATE</td></tr><p>" >> $PIKVMSITE
    printf "    https://%-30s\t%-4s\t$STATUS\n" $SITE "up"
    let count=$count+1
  fi
done

# Add up total required upgrades/unknown versions
let totalreq=$upgrade+$unknown

# Show some relevant status information in html page as well as show user how to access the website
echo "<p><b>Found $count out of $totalhosts websites that are available.<p>" >> $PIKVMSITE
echo "<p>Latest KVMD version is <strong style=\"color: darkred;\">$KVMDNEW</strong>.&nbsp Found $totalreq systems on older/unknown kvmd versions.<p></b>" >> $PIKVMSITE
printf "\n    --- Please point a browser to http://$(hostname)/pikvm.html ---\n"

# Add html to be able to sort by URL or Website Status just by clicking the column titles
cat << END_HTML >> $PIKVMSITE
</table></div>
<script charset="utf-8">var TGSort=window.TGSort||function(n){"use strict";function r(n){return n?n.length:0}function t(n,t,e,o=0){for(e=r(n);o<e;++o)t(n[o],o)}function e(n){return n.split("").reverse().join("")}function o(n){var e=n[0];return t(n,function(n){for(;!n.startsWith(e);)e=e.substring(0,r(e)-1)}),r(e)}function u(n,r,e=[]){return t(n,function(n){r(n)&&e.push(n)}),e}var a=parseFloat;function i(n,r){return function(t){var e="";return t.replace(n,function(n,t,o){return e=t.replace(r,"")+"."+(o||"").substring(1)}),a(e)}}var s=i(/^(?:\s*)([+-]?(?:\d+)(?:,\d{3})*)(\.\d*)?$/g,/,/g),c=i(/^(?:\s*)([+-]?(?:\d+)(?:\.\d{3})*)(,\d*)?$/g,/\./g);function f(n){var t=a(n);return!isNaN(t)&&r(""+t)+1>=r(n)?t:NaN}function d(n){var e=[],o=n;return t([f,s,c],function(u){var a=[],i=[];t(n,function(n,r){r=u(n),a.push(r),r||i.push(n)}),r(i)<r(o)&&(o=i,e=a)}),r(u(o,function(n){return n==o[0]}))==r(o)?e:[]}function v(n){if("TABLE"==n.nodeName){for(var a=function(r){var e,o,u=[],a=[];return function n(r,e){e(r),t(r.childNodes,function(r){n(r,e)})}(n,function(n){"TR"==(o=n.nodeName)?(e=[],u.push(e),a.push(n)):"TD"!=o&&"TH"!=o||e.push(n)}),[u,a]}(),i=a[0],s=a[1],c=r(i),f=c>1&&r(i[0])<r(i[1])?1:0,v=f+1,p=i[f],h=r(p),l=[],g=[],N=[],m=v;m<c;++m){for(var T=0;T<h;++T){r(g)<h&&g.push([]);var C=i[m][T],L=C.textContent||C.innerText||"";g[T].push(L.trim())}N.push(m-v)}t(p,function(n,t){l[t]=0;var a=n.classList;a.add("tg-sort-header"),n.addEventListener("click",function(){var n=l[t];!function(){for(var n=0;n<h;++n){var r=p[n].classList;r.remove("tg-sort-asc"),r.remove("tg-sort-desc"),l[n]=0}}(),(n=1==n?-1:+!n)&&a.add(n>0?"tg-sort-asc":"tg-sort-desc"),l[t]=n;var i,f=g[t],m=function(r,t){return n*f[r].localeCompare(f[t])||n*(r-t)},T=function(n){var t=d(n);if(!r(t)){var u=o(n),a=o(n.map(e));t=d(n.map(function(n){return n.substring(u,r(n)-a)}))}return t}(f);(r(T)||r(T=r(u(i=f.map(Date.parse),isNaN))?[]:i))&&(m=function(r,t){var e=T[r],o=T[t],u=isNaN(e),a=isNaN(o);return u&&a?0:u?-n:a?n:e>o?n:e<o?-n:n*(r-t)});var C,L=N.slice();L.sort(m);for(var E=v;E<c;++E)(C=s[E].parentNode).removeChild(s[E]);for(E=v;E<c;++E)C.appendChild(s[v+L[E-v]])})})}}n.addEventListener("DOMContentLoaded",function(){for(var t=n.getElementsByClassName("tg"),e=0;e<r(t);++e)try{v(t[e])}catch(n){}})}(document)</script>
</html>
END_HTML
