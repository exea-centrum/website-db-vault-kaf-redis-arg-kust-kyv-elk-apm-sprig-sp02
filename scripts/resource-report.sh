#!/usr/bin/env bash
# resource-report.sh — kompletny raport pamieci i CPU: wezel, kazdy pod/kontener (requests, limity, REALNE uzycie),
# sumy per namespace oraz analiza manifestow w manifests/base (replicas, requests, limits).
#
# Uzycie (z katalogu repo):
#   ./scripts/resource-report.sh                 # caly klaster + manifesty z manifests/base
#   ./scripts/resource-report.sh -n davtro02     # tylko jeden namespace w czesci podow
#   ./scripts/resource-report.sh -m manifests/overlays/production   # manifesty z innego katalogu
#   ./scripts/resource-report.sh -o raport.txt   # dodatkowo zapis do pliku
# Wymaga: kubectl (microk8s kubectl), python3. 'kubectl top' wymaga dzialajacego metrics-server
# (jesli nie dziala, raport pokaze tylko requests/limits i zaznaczy brak metryk).
set -uo pipefail

NS_FILTER=""
MANIFESTS="manifests/base"
OUT=""
while getopts "n:m:o:h" o; do
  case $o in
    n) NS_FILTER="$OPTARG" ;;
    m) MANIFESTS="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    h|*) sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

if [ -n "$OUT" ]; then exec > >(tee "$OUT") 2>&1; fi

if command -v kubectl >/dev/null 2>&1; then KC="kubectl"
elif command -v microk8s >/dev/null 2>&1; then KC="microk8s kubectl"
else echo "Brak kubectl/microk8s w PATH." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "Brak python3." >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
hdr(){ printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }

hdr "1. WEZEL: pamiec, swap, obciazenie"
echo "Czas: $(date '+%F %T')"
free -h 2>/dev/null || true
echo
swapon --show 2>/dev/null || echo "(swap: brak informacji)"
echo
echo "load average: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)  | rdzenie: $(nproc 2>/dev/null)"
echo
echo "--- kubectl top node ---"
timeout 30 $KC top node 2>&1 | head -5 || echo "(top node niedostepne)"
echo
echo "--- Allocated resources (requests/limits wezla wg schedulera) ---"
timeout 60 $KC describe node 2>/dev/null | sed -n '/^Capacity:/,/^System Info:/p' | grep -E 'Capacity|Allocatable|cpu|memory|pods|ephemeral' | head -12
timeout 60 $KC describe node 2>/dev/null | sed -n '/^Allocated resources:/,/^Events:/p' | head -10

hdr "2. Zbieranie danych z klastra (pody + metryki)"
NSARG="-A"; [ -n "$NS_FILTER" ] && NSARG="-n $NS_FILTER"
if timeout 90 $KC get pods $NSARG -o json > "$TMP/pods.json" 2>"$TMP/pods.err"; then
  echo "pody: OK"
else
  echo "Nie udalo sie pobrac podow (API przeciazone?): $(head -c 300 "$TMP/pods.err")"; echo '{"items":[]}' > "$TMP/pods.json"
fi
if timeout 90 $KC top pods $NSARG --containers --no-headers > "$TMP/top.txt" 2>"$TMP/top.err"; then
  echo "metryki (kubectl top): OK ($(wc -l < "$TMP/top.txt") wierszy)"
else
  echo "UWAGA: brak metryk (metrics-server): $(head -c 200 "$TMP/top.err")"; : > "$TMP/top.txt"
fi

hdr "3. PODY: requests / limity / realne uzycie (posortowane wg requests pamieci)"
NSF="$NS_FILTER" python3 - "$TMP/pods.json" "$TMP/top.txt" <<'PY'
import json, sys, os, collections

def mem(q):
    if q is None: return 0.0
    q=str(q)
    u={'Ki':1/1024,'Mi':1,'Gi':1024,'Ti':1024*1024,'k':1000/1048576,'K':1000/1048576,'M':1e6/1048576,'G':1e9/1048576}
    for s in ('Ki','Mi','Gi','Ti'):
        if q.endswith(s): return float(q[:-2])*u[s]
    for s in ('k','K','M','G'):
        if q.endswith(s): return float(q[:-1])*u[s]
    try: return float(q)/1048576
    except: return 0.0

def cpu(q):
    if q is None: return 0.0
    q=str(q)
    if q.endswith('n'): return float(q[:-1])/1e6
    if q.endswith('u'): return float(q[:-1])/1e3
    if q.endswith('m'): return float(q[:-1])
    try: return float(q)*1000
    except: return 0.0

pods=json.load(open(sys.argv[1]))['items']
top={}   # (ns,pod,container) -> (cpu_m, mem_mi)
for line in open(sys.argv[2]):
    p=line.split()
    if len(p)>=5:
        top[(p[0],p[1],p[2])]=(cpu(p[3]),mem(p[4]))
    # kubectl top bez -A: brak kolumny namespace (4 kolumny); obsluz
    elif len(p)==4:
        top[(os.environ.get('NSF',''),p[0],p[1])]=(cpu(p[2]),mem(p[3]))
have_top=bool(top)

rows=[]; nsagg=collections.defaultdict(lambda:[0,0,0,0,0,0,0])
for pod in pods:
    ns=pod['metadata']['namespace']; name=pod['metadata']['name']
    st=pod['status']; phase=st.get('phase','?')
    cs={c['name']:c for c in st.get('containerStatuses',[])}
    restarts=sum(c.get('restartCount',0) for c in cs.values())
    reason=phase
    for c in cs.values():
        w=c.get('state',{}).get('waiting')
        if w and w.get('reason'): reason=w['reason']
    mr=ml=cr=cl=0.0; mu=cu=0.0; istio=0.0; nores=[]
    for c in pod['spec'].get('containers',[]):
        r=c.get('resources',{}); rq=r.get('requests',{}); lm=r.get('limits',{})
        a,b=mem(rq.get('memory')),mem(lm.get('memory'))
        mr+=a; ml+=b; cr+=cpu(rq.get('cpu')); cl+=cpu(lm.get('cpu'))
        if c['name']=='istio-proxy': istio+=a
        if not rq: nores.append(c['name'])
        t=top.get((ns,name,c['name']))
        if t: cu+=t[0]; mu+=t[1]
    flag=[]
    if phase=='Pending': flag.append('PENDING')
    if reason not in ('Running','Succeeded','Pending'): flag.append(reason)
    if ml and mu>0.9*ml: flag.append('blisko limitu RAM')
    if nores: flag.append('bez requests: '+','.join(nores))
    if restarts>=10: flag.append('restarty')
    # pody Pending nie zajmuja pamieci na wezle, ale licz je osobno
    rows.append((mr,ns,name,reason,restarts,mr,ml,mu,cr,cl,cu,istio,flag,phase))
    a=nsagg[ns]
    if phase=='Running':
        a[0]+=mr; a[1]+=mu; a[2]+=cr; a[3]+=cu; a[4]+=istio
    else:
        a[5]+=mr
    a[6]+=1

rows.sort(reverse=True)
f="{:<18} {:<46} {:<17} {:>4} | {:>6} {:>6} {:>6} | {:>6} {:>6} {:>6} | {}"
print(f.format('NAMESPACE','POD','STATUS','RST','RAMreq','RAMlim','RAMuse','CPUreq','CPUlim','CPUuse','UWAGI'))
print('-'*150)
for r in rows:
    mr,ns,name,reason,rs,_,ml,mu,cr,cl,cu,istio,flag,phase=r
    use=lambda v: ('%d'%v if have_top and v>0 else '-')
    print(f.format(ns[:18],name[:46],reason[:17],rs,'%d'%mr,'%d'%ml if ml else '-',use(mu),'%d'%cr,'%d'%cl if cl else '-',use(cu),'; '.join(flag)))
print('\nJednostki: RAM w Mi, CPU w mCPU. RAMreq/CPUreq = suma requests kontenerow (z sidecarami).')
if not have_top: print('(brak metryk: kolumny *use* puste)')

print('\n--- SUMY per namespace (tylko pody Running) ---')
g="{:<22} {:>5} {:>9} {:>9} {:>9} {:>9} {:>11} {:>11}"
print(g.format('NAMESPACE','pody','RAMreq','RAMuse','CPUreq','CPUuse','istio-proxy','Pending RAM'))
tot=[0]*7
for ns,a in sorted(nsagg.items(), key=lambda kv:-kv[1][0]):
    print(g.format(ns[:22],a[6],'%d'%a[0],'%d'%a[1] if have_top else '-','%d'%a[2],'%d'%a[3] if have_top else '-','%d'%a[4],'%d'%a[5]))
    for i in range(7): tot[i]+=a[i]
print(g.format('RAZEM',tot[6],'%d'%tot[0],'%d'%tot[1] if have_top else '-','%d'%tot[2],'%d'%tot[3] if have_top else '-','%d'%tot[4],'%d'%tot[5]))
print('\nsidecary istio-proxy lacznie: %d Mi requests'%tot[4])

print('\n--- TOP 10 pod wzgledem REALNEGO uzycia RAM ---' if have_top else '')
if have_top:
    byuse=sorted(rows,key=lambda r:-r[7])[:10]
    for r in byuse:
        print('  %6d Mi  (req %d Mi)  %s/%s'%(r[7],r[5],r[1],r[2]))
    over=[r for r in rows if r[13]=='Running' and r[5]>0 and r[7]>0 and r[7]<0.4*r[5]]
    if over:
        print('\n--- requests ZAWYZONE (uzycie < 40% requests) — kandydaci do obciecia ---')
        for r in sorted(over,key=lambda r:-(r[5]-r[7]))[:10]:
            print('  requests %5d Mi, uzycie %5d Mi, do odzyskania ~%d Mi  %s/%s'%(r[5],r[7],r[5]-r[7],r[1],r[2]))
PY

hdr "4. MANIFESTY: $MANIFESTS (replicas, requests, limits na kontener)"
python3 - "$MANIFESTS" <<'PY'
import sys, os, glob
try:
    import yaml
except ImportError:
    print("Brak modulu PyYAML (pip install --break-system-packages pyyaml) — pomijam analize manifestow."); sys.exit(0)

def mem(q):
    if q is None: return 0.0
    q=str(q); u={'Ki':1/1024,'Mi':1,'Gi':1024}
    for s in u:
        if q.endswith(s): return float(q[:-len(s)])*u[s]
    try: return float(q)/1048576
    except: return 0.0
def cpu(q):
    if q is None: return 0.0
    q=str(q)
    if q.endswith('m'): return float(q[:-1])
    try: return float(q)*1000
    except: return 0.0

root=sys.argv[1]
files=sorted(glob.glob(os.path.join(root,'*.yaml')))
if not files: print('Brak plikow *.yaml w',root); sys.exit(0)
tot_m=tot_c=0.0
f="{:<30} {:<12} {:<28} {:>4} {:<22} {:>7} {:>7} {:>7} {:>7}"
print(f.format('PLIK','KIND','NAZWA','REPL','KONTENER','RAMreq','RAMlim','CPUreq','CPUlim'))
print('-'*135)
for fn in files:
    try: docs=list(yaml.safe_load_all(open(fn)))
    except Exception as e: print('  [blad YAML]',fn,str(e)[:80]); continue
    for d in docs:
        if not isinstance(d,dict): continue
        k=d.get('kind');
        if k not in ('Deployment','StatefulSet','DaemonSet','Job','CronJob'): continue
        name=d.get('metadata',{}).get('name','?'); spec=d.get('spec',{})
        if k=='CronJob': spec=spec.get('jobTemplate',{}).get('spec',{})
        repl=spec.get('replicas','1') if k in('Deployment','StatefulSet') else ('ds' if k=='DaemonSet' else '-')
        tpl=spec.get('template',{}); ann=tpl.get('metadata',{}).get('annotations',{}) or {}
        sidecar='nie' if (tpl.get('metadata',{}).get('labels',{}) or {}).get('sidecar.istio.io/inject')=='false' or ann.get('sidecar.istio.io/inject')=='false' else 'tak'
        try: n=float(repl)
        except: n=1.0
        for c in tpl.get('spec',{}).get('containers',[]) or []:
            r=c.get('resources',{}) or {}; rq=r.get('requests',{}) or {}; lm=r.get('limits',{}) or {}
            tot_m+=mem(rq.get('memory'))*n; tot_c+=cpu(rq.get('cpu'))*n
            print(f.format(os.path.basename(fn)[:30],k[:12],name[:28],str(repl),c['name'][:22],
                           rq.get('memory','-'),lm.get('memory','-'),rq.get('cpu','-'),lm.get('cpu','-')) + ('  [BRAK resources]' if not r else ''))
print('\nRAZEM requests z manifestow (bez sidecarow istio): RAM ~%d Mi, CPU ~%d m (repliki z manifestu; overlay/HPA moga je zmieniac)'%(tot_m,tot_c))
PY

hdr "5. Najczestsze przyczyny problemow (skrot)"
cat <<'EOF'
- RAMreq wezla bliskie 100% => nowe pody beda Pending ("Insufficient memory"), a scheduler zaczyna wypychac na swap.
- Duzo swapu + load average >> liczba rdzeni => API server/kubelet odpowiadaja wolno (timeouty sond, "TLS handshake timeout").
- "requests ZAWYZONE" => da sie obciac bez utraty dzialania; "blisko limitu RAM" => ryzyko OOMKilled.
- Zmiany robimy w gicie (overlays/production), bo selfHeal cofa reczne 'kubectl scale'.
EOF