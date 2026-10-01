#!/bin/bash
set -e

PROJECT_NAME="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
NAMESPACE="davtro02"
REPO="https://github.com/exea-centrum/${PROJECT_NAME}.git"

echo "=== DavTro Rentals - Istio Edition (mTLS via Envoy, no app-level TLS) ==="
mkdir -p ${PROJECT_NAME}/{frontend,backend-fastapi/app/{templates,static},java-app/src/main/{java/com/davtro/rental/{model,repository,consumer,service},resources},spark-jobs/src/main/scala/com/davtro/jobs,spark-jobs/project,manifests/{base,overlays/{production,staging},argocd},terraform,.github/workflows,docs,kyverno-policies,argocd,istio}

# ============================================
# GIT
# ============================================

cat > ${PROJECT_NAME}/.gitignore << 'EOF'
__pycache__/
*.pyc
.venv/
target/
node_modules/
*.jks
*.p12
*.crt
*.key
EOF

# ============================================
# FRONTEND (bez zmian – nginx-unprivileged, proxy do FastAPI)
# ============================================
cat > ${PROJECT_NAME}/frontend/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DavTro Rentals - Wynajem Krótkoterminowy</title>
<script src="https://cdn.tailwindcss.com"></script>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
body{font-family:'Inter',sans-serif;}
.glass{background:rgba(255,255,255,0.1);backdrop-filter:blur(12px);border:1px solid rgba(255,255,255,0.2);}
.property-card{transition:all .3s ease;}
.property-card:hover{transform:translateY(-8px);}
</style>
</head>
<body class="bg-gradient-to-br from-slate-900 via-blue-900 to-slate-900 text-white min-h-screen">
<nav class="fixed top-0 left-0 right-0 z-50 glass">
  <div class="container mx-auto px-6 py-4 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 bg-blue-500 rounded-xl flex items-center justify-center"><i class="fas fa-home text-white"></i></div>
      <div><h1 class="text-xl font-bold">DavTro<span class="text-blue-400">Rentals</span></h1></div>
    </div>
    <div class="flex gap-6">
      <button onclick="showSection('home')" class="nav-btn text-gray-300 hover:text-white font-medium">Strona Główna</button>
      <button onclick="showSection('properties')" class="nav-btn text-gray-300 hover:text-white font-medium">Nieruchomości</button>
      <button onclick="showSection('calendar')" class="nav-btn text-gray-300 hover:text-white font-medium">Rezerwacje</button>
      <button onclick="showSection('admin')" class="nav-btn text-gray-300 hover:text-white font-medium" id="nav-admin-label">Admin</button>
      <span id="nav-user" class="hidden items-center gap-2 text-blue-300"><i class="fas fa-user-circle"></i><span id="nav-username"></span><button onclick="logout()" class="text-gray-400 hover:text-white text-sm underline">Wyloguj</button></span>
      <button id="nav-login" onclick="showSection('login')" class="nav-btn text-blue-300 hover:text-white font-medium">Zaloguj</button>
    </div>
  </div>
</nav>
<main class="pt-24 pb-12">
  <section id="home-section" class="section-content container mx-auto px-6">
    <div class="text-center mb-16">
      <h1 class="text-5xl font-bold mb-6 bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">Wynajem Krótkoterminowy Premium</h1>
      <p class="text-xl text-gray-400 max-w-2xl mx-auto mb-10">Platforma z Istio mTLS, Kafka, Redis, PostgreSQL, Vault i Spark</p>
      <div class="flex justify-center gap-4">
        <button onclick="showSection('properties')" class="px-8 py-4 bg-blue-600 rounded-xl font-semibold hover:scale-105 transition">Przeglądaj Oferty</button>
        <button onclick="showSection('calendar')" class="px-8 py-4 glass rounded-xl font-semibold hover:scale-105 transition">Sprawdź Dostępność</button>
      </div>
    </div>
    <div class="grid md:grid-cols-4 gap-6 mb-12">
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-shield-alt text-3xl text-cyan-400 mb-3"></i><h3 class="font-bold">Istio mTLS</h3><p class="text-sm text-gray-400">Zero-trust L7</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-bolt text-3xl text-yellow-400 mb-3"></i><h3 class="font-bold">Apache Kafka</h3><p class="text-sm text-gray-400">Event streaming</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-server text-3xl text-red-400 mb-3"></i><h3 class="font-bold">Redis + Postgres</h3><p class="text-sm text-gray-400">Cache + trwały zapis</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-lock text-3xl text-purple-400 mb-3"></i><h3 class="font-bold">Vault Transit</h3><p class="text-sm text-gray-400">PII szyfrowane w spoczynku</p></div>
    </div>
    <h2 class="text-3xl font-bold text-center mb-10">Wyróżnione Nieruchomości</h2>
    <div class="grid md:grid-cols-3 gap-8" id="featured-properties"></div>
  </section>
  <section id="properties-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Nasze Nieruchomości</h2>
    <div class="grid md:grid-cols-3 gap-8" id="all-properties"></div>
  </section>
  <section id="calendar-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Kalendarz Rezerwacji</h2>
    <div class="grid lg:grid-cols-3 gap-8">
      <div class="lg:col-span-2 glass rounded-2xl p-6">
        <div class="flex items-center justify-between mb-6">
          <button onclick="changeMonth(-1)" class="w-10 h-10 rounded-lg bg-white/10 hover:bg-white/20"><i class="fas fa-chevron-left"></i></button>
          <h3 class="text-xl font-bold" id="calendar-month">Wrzesień 2026</h3>
          <button onclick="changeMonth(1)" class="w-10 h-10 rounded-lg bg-white/10 hover:bg-white/20"><i class="fas fa-chevron-right"></i></button>
        </div>
        <div class="grid grid-cols-7 gap-2 mb-4 text-center text-sm text-gray-400">
          <div>Pon</div><div>Wt</div><div>Śr</div><div>Czw</div><div>Pt</div><div>Sob</div><div>Nd</div>
        </div>
        <div class="grid grid-cols-7 gap-2" id="calendar-grid"></div>
      </div>
      <div class="glass rounded-2xl p-6">
        <h3 class="text-xl font-bold mb-6">Formularz Rezerwacji</h3>
        <div class="space-y-4">
          <div><label class="block text-sm text-gray-400 mb-2">Nieruchomość</label><select id="booking-property" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white"></select></div>
          <div class="grid grid-cols-2 gap-4">
            <div><label class="block text-sm text-gray-400 mb-2">Przyjazd</label><input type="date" id="check-in" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white"></div>
            <div><label class="block text-sm text-gray-400 mb-2">Wyjazd</label><input type="date" id="check-out" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white"></div>
          </div>
          <div><label class="block text-sm text-gray-400 mb-2">Imię i nazwisko</label><input type="text" id="guest-name" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="Jan Kowalski"></div>
          <div><label class="block text-sm text-gray-400 mb-2">Email</label><input type="email" id="guest-email" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="jan@example.com"></div>
          <div><label class="block text-sm text-gray-400 mb-2">Telefon</label><input type="tel" id="guest-phone" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="+48 123 456 789"></div>
          <div class="bg-white/5 rounded-lg p-4">
            <div class="flex justify-between text-sm mb-2"><span>Cena za dobę:</span><span id="price-per-night" class="font-semibold">-</span></div>
            <div class="flex justify-between text-sm mb-2"><span>Liczba nocy:</span><span id="night-count" class="font-semibold">-</span></div>
            <div class="flex justify-between text-lg font-bold border-t border-white/10 pt-2"><span>Razem:</span><span id="total-price" class="text-blue-400">-</span></div>
          </div>
          <button onclick="submitBooking()" class="w-full py-4 bg-gradient-to-r from-blue-600 to-purple-600 rounded-xl font-bold hover:scale-[1.02] transition">Zarezerwuj i Otrzymaj Fakturę Proforma</button>
          <p class="text-xs text-gray-500 text-center"><i class="fas fa-lock mr-1"></i>Istio mTLS: FastAPI ↔ Postgres/Kafka/Redis szyfrowane przez Envoy</p>
        </div>
      </div>
    </div>
  </section>
  <section id="admin-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Panel Administracyjny</h2>
    <div class="grid md:grid-cols-4 gap-6 mb-10">
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-blue-400" id="stat-bookings">0</div><div class="text-sm text-gray-400">Rezerwacje</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-green-400" id="stat-revenue">0 zł</div><div class="text-sm text-gray-400">Przychód</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-yellow-400" id="stat-kafka">0</div><div class="text-sm text-gray-400">Wiadomości Kafka</div></div>
      <div class="glass rounded-2xl p-6 text-center"><div class="text-4xl font-bold text-purple-400" id="stat-occupancy">0%</div><div class="text-sm text-gray-400">Zajętość</div></div>
    </div>
    <div class="glass rounded-2xl p-6 mb-10">
      <div class="flex justify-between mb-6"><h3 class="text-xl font-bold">Rezerwacje</h3><button onclick="exportBookings()" class="px-4 py-2 bg-blue-600 rounded-lg"><i class="fas fa-download mr-2"></i>Eksport CSV</button></div>
      <div class="overflow-x-auto"><table class="w-full text-left"><thead><tr class="border-b border-white/10"><th class="pb-4 text-gray-400">ID</th><th class="pb-4 text-gray-400">Nieruchomość</th><th class="pb-4 text-gray-400">Gość</th><th class="pb-4 text-gray-400">Daty</th><th class="pb-4 text-gray-400">Kwota</th><th class="pb-4 text-gray-400">Status</th></tr></thead><tbody id="bookings-table"></tbody></table></div>
    </div>
    <div id="admin-password-card" class="hidden glass rounded-2xl p-6 mb-10">
      <h3 class="text-xl font-bold mb-4"><i class="fas fa-user-shield text-purple-400 mr-2"></i>Zmiana hasła użytkownika (tylko admin)</h3>
      <div class="flex flex-wrap gap-3">
        <input id="adm-username" class="flex-1 min-w-48 bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="Login użytkownika, np. jan">
        <input id="adm-newpass" type="password" class="flex-1 min-w-48 bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="Nowe hasło (min. 6 znaków)">
        <button onclick="adminSetPassword()" class="px-6 py-3 bg-purple-600 rounded-lg font-semibold hover:bg-purple-700 transition">Ustaw hasło</button>
      </div>
    </div>
    <div class="glass rounded-2xl p-6">
      <h3 class="text-xl font-bold mb-6">Kafka Topics</h3>
      <div class="grid md:grid-cols-3 gap-4">
        <div class="bg-slate-800/50 rounded-xl p-4 border border-yellow-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-yellow-400">bookings-created</span><span class="text-xs bg-yellow-500/20 text-yellow-400 px-2 py-1 rounded">spring-app</span></div><div class="text-2xl font-bold" id="topic-bookings-created">–</div></div>
        <div class="bg-slate-800/50 rounded-xl p-4 border border-purple-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-purple-400">marketing-actions</span><span class="text-xs bg-purple-500/20 text-purple-400 px-2 py-1 rounded">spark-app</span></div><div class="text-2xl font-bold" id="topic-marketing-actions">–</div></div>
        <div class="bg-slate-800/50 rounded-xl p-4 border border-green-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-green-400">email-invoices</span><span class="text-xs bg-green-500/20 text-green-400 px-2 py-1 rounded">message-processor</span></div><div class="text-2xl font-bold" id="topic-email-invoices">–</div></div>
      </div>
    </div>
  </section>
  <section id="login-section" class="section-content hidden container mx-auto px-6">
    <h2 class="text-4xl font-bold text-center mb-10">Logowanie rezerwującego</h2>
    <div class="max-w-md mx-auto glass rounded-2xl p-8">
      <div class="flex gap-2 mb-6">
        <button id="tab-login" onclick="switchAuthTab('login')" class="flex-1 py-2 rounded-lg bg-blue-600 font-semibold">Logowanie</button>
        <button id="tab-register" onclick="switchAuthTab('register')" class="flex-1 py-2 rounded-lg bg-white/10 font-semibold">Rejestracja</button>
      </div>
      <div class="space-y-4">
        <div><label class="block text-sm text-gray-400 mb-2">Login</label><input type="text" id="auth-username" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="np. jan.kowalski"></div>
        <div><label class="block text-sm text-gray-400 mb-2">Hasło</label><input type="password" id="auth-password" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="••••••••"></div>
        <div id="register-fields" class="hidden space-y-4">
          <div><label class="block text-sm text-gray-400 mb-2">Imię i nazwisko</label><input type="text" id="auth-fullname" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="Jan Kowalski"></div>
          <div><label class="block text-sm text-gray-400 mb-2">Email</label><input type="email" id="auth-email" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="jan@example.com"></div>
        </div>
        <button onclick="submitAuth()" id="auth-submit" class="w-full py-4 bg-gradient-to-r from-blue-600 to-purple-600 rounded-xl font-bold hover:scale-[1.02] transition">Zaloguj się</button>
        <p class="text-xs text-gray-500 text-center"><i class="fas fa-shield-alt mr-1"></i>Hasła: PBKDF2; sesja: Redis; transport: Istio mTLS.</p>
        <div id="password-change" class="hidden border-t border-white/10 pt-4 mt-2">
          <h4 class="font-bold mb-3"><i class="fas fa-key text-blue-400 mr-2"></i>Zmiana własnego hasła</h4>
          <div class="space-y-3">
            <input type="password" id="pw-current" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="Aktualne hasło">
            <input type="password" id="pw-new" class="w-full bg-slate-800 border border-white/20 rounded-lg px-4 py-3 text-white" placeholder="Nowe hasło (min. 6 znaków)">
            <button onclick="changePassword()" class="w-full py-3 bg-blue-600 rounded-lg font-semibold hover:bg-blue-700 transition">Zmień hasło</button>
          </div>
        </div>
      </div>
    </div>
  </section>
</main>
<div id="toast" class="fixed bottom-6 right-6 z-50 transform translate-y-20 opacity-0 transition-all duration-300">
  <div class="glass rounded-xl px-6 py-4 flex items-center gap-3 border-l-4 border-blue-500">
    <i id="toast-icon" class="fas fa-check-circle text-green-400 text-xl"></i>
    <div><div id="toast-title" class="font-semibold">Sukces</div><div id="toast-message" class="text-sm text-gray-400">Operacja zakończona</div></div>
  </div>
</div>
<script>
const PROPERTY_META=[
  {id:1,name:"Apartament Premium - Warszawa",location:"warsaw",price:450,guests:4,image:"🏙️",rating:4.9,amenities:["WiFi","Klimatyzacja","Balkon","Parking"],description:"Luksusowy apartament w centrum Warszawy."},
  {id:2,name:"Studio Modern - Kraków",location:"krakow",price:320,guests:2,image:"🏰",rating:4.8,amenities:["WiFi","Smart TV","Kuchnia"],description:"Stylowe studio obok Rynku Głównego."},
  {id:3,name:"Villa nad Morzem - Gdańsk",location:"gdansk",price:680,guests:6,image:"🌊",rating:4.9,amenities:["WiFi","Ogródek","Grill","Parking"],description:"Willa 200m od plaży."},
  {id:4,name:"Loft Industrial - Wrocław",location:"wroclaw",price:280,guests:3,image:"🏭",rating:4.7,amenities:["WiFi","Projektor","Klimatyzacja"],description:"Industrialny loft w Nadodrzu."},
  {id:5,name:"Penthouse View - Warszawa",location:"warsaw",price:850,guests:4,image:"🌆",rating:5.0,amenities:["WiFi","Basen","Siłownia","Concierge"],description:"Ekskluzywny penthouse z tarasem."},
  {id:6,name:"Apartament Royal - Kraków",location:"krakow",price:390,guests:4,image:"👑",rating:4.8,amenities:["WiFi","Klimatyzacja","Balkon"],description:"Elegancki apartament w Kazimierzu."}
];
let properties=[];let bookings=[];let currentUser=null;
let authToken=localStorage.getItem('davtro_token')||null;
function authHeaders(){return authToken?{'Authorization':'Bearer '+authToken}:{}}
let kafkaTopics={};let currentMonth=new Date();let selectedDates=[];
async function apiJson(path,options){options=Object.assign({},options||{});options.headers=Object.assign({},options.headers||{},authHeaders());const res=await fetch(path,options);if(!res.ok){const body=(await res.text()).slice(0,180);throw new Error('HTTP '+res.status+' '+body);}return res.json();}
function mapProperty(p){const meta=PROPERTY_META.find(m=>String(m.id)===String(p.id))||{};return{id:p.id,name:p.name,location:p.location,price:Number(p.price),guests:p.guests,description:p.description||'',amenities:Array.isArray(p.amenities)?p.amenities:[],image:meta.image||'🏠',rating:meta.rating||4.8};}
function mapBooking(b){const ci=b.check_in,co=b.check_out;return{id:b.id,propertyId:b.property_id,propertyName:b.property_name,guestName:b.guest_name,email:b.email,phone:b.phone||'',checkIn:ci,checkOut:co,nights:Math.max(0,Math.round((new Date(co)-new Date(ci))/86400000)),totalPrice:b.total_price==null?null:Number(b.total_price),status:b.status,createdAt:b.created_at,masked:!!b.masked,mine:!!b.mine};}
async function loadProperties(){try{properties=(await apiJson('/api/properties')).map(mapProperty);}catch(e){console.error('GET /api/properties:',e);showToast('Błąd','Brak danych z API: '+e.message,'error');}}
async function loadBookings(){try{bookings=(await apiJson('/api/bookings')).map(mapBooking);}catch(e){bookings=[];console.error('GET /api/bookings:',e);}}
async function loadKafkaMetrics(){try{const text=await (await fetch('/kafka-metrics')).text();const counts={};text.split('\n').forEach(line=>{const m=line.match(/^kafka_topic_partition_current_offset\{[^}]*topic="([^"]+)"[^}]*\}\s+(\d+)/);if(m)counts[m[1]]=(counts[m[1]]||0)+Number(m[2]);});kafkaTopics=counts;}catch(e){kafkaTopics={};}}
async function showSection(section){document.querySelectorAll('.section-content').forEach(s=>s.classList.add('hidden'));document.getElementById(section+'-section').classList.remove('hidden');if(section==='properties')renderProperties();if(section==='calendar'){renderCalendar();populatePropertySelect();}if(section==='login')renderLoginSection();if(section==='admin'){document.getElementById('bookings-table').innerHTML='<tr><td colspan="6" class="py-8 text-center text-gray-500">Ładowanie…</td></tr>';await loadBookings();await loadKafkaMetrics();renderAdmin();}}
function showToast(title,message,type='success'){const toast=document.getElementById('toast');document.getElementById('toast-title').textContent=title;document.getElementById('toast-message').textContent=message;toast.classList.remove('translate-y-20','opacity-0');setTimeout(()=>toast.classList.add('translate-y-20','opacity-0'),4000);}
function createPropertyCard(prop){return`<div class="property-card glass rounded-2xl overflow-hidden"><div class="h-48 bg-gradient-to-br from-slate-700 to-slate-800 flex items-center justify-center text-6xl relative">${prop.image}<div class="absolute top-4 right-4 bg-black/50 rounded-lg px-3 py-1 text-sm font-bold"><i class="fas fa-star text-yellow-400 mr-1"></i>${prop.rating}</div></div><div class="p-6"><div class="flex items-center gap-2 text-sm text-gray-400 mb-2"><i class="fas fa-map-marker-alt text-blue-400"></i>${prop.location}</div><h3 class="text-lg font-bold mb-2">${prop.name}</h3><p class="text-sm text-gray-400 mb-4">${prop.description}</p><div class="flex flex-wrap gap-2 mb-4">${prop.amenities.map(a=>`<span class="text-xs bg-white/10 px-2 py-1 rounded">${a}</span>`).join('')}</div><div class="flex items-center justify-between"><div><span class="text-2xl font-bold text-blue-400">${prop.price} zł</span><span class="text-sm text-gray-400">/doba</span></div><button onclick="selectPropertyForBooking(${prop.id})" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition">Rezerwuj</button></div></div></div>`;}
function renderProperties(){document.getElementById('all-properties').innerHTML=properties.map(p=>createPropertyCard(p)).join('');}
function renderFeatured(){document.getElementById('featured-properties').innerHTML=properties.slice(0,3).map(p=>createPropertyCard(p)).join('');}
function renderCalendar(){const grid=document.getElementById('calendar-grid');const monthLabel=document.getElementById('calendar-month');const year=currentMonth.getFullYear(),month=currentMonth.getMonth();const monthNames=['Styczeń','Luty','Marzec','Kwiecień','Maj','Czerwiec','Lipiec','Sierpień','Wrzesień','Październik','Listopad','Grudzień'];monthLabel.textContent=`${monthNames[month]} ${year}`;grid.innerHTML='';const firstDay=new Date(year,month,1).getDay();const daysInMonth=new Date(year,month+1,0).getDate();const startOffset=firstDay===0?6:firstDay-1;for(let i=0;i<startOffset;i++)grid.innerHTML+=`<div></div>`;for(let day=1;day<=daysInMonth;day++){const dateStr=`${year}-${String(month+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;const calProp=document.getElementById('booking-property')?.value;const isBooked=bookings.some(b=>dateStr>=b.checkIn&&dateStr<=b.checkOut&&(!calProp||String(b.propertyId)===String(calProp)));const isSelected=selectedDates.includes(dateStr);const isPast=new Date(dateStr)<new Date().setHours(0,0,0,0);let classes='h-12 rounded-lg flex items-center justify-center cursor-pointer text-sm font-medium ';if(isPast)classes+='text-gray-600 cursor-not-allowed';else if(isBooked)classes+='bg-red-500/20 border border-red-500 text-red-300 cursor-not-allowed';else if(isSelected)classes+='bg-blue-500 border border-blue-400 text-white';else classes+='bg-white/5 hover:bg-white/15';const onclick=isPast||isBooked?'':`onclick="toggleDate('${dateStr}')"`;grid.innerHTML+=`<div class="${classes}" ${onclick}>${day}</div>`;}}
function changeMonth(delta){currentMonth.setMonth(currentMonth.getMonth()+delta);renderCalendar();}
function toggleDate(dateStr){const idx=selectedDates.indexOf(dateStr);if(idx>-1)selectedDates.splice(idx,1);else if(selectedDates.length<2)selectedDates.push(dateStr);else{selectedDates=[selectedDates[1],dateStr];}selectedDates.sort();renderCalendar();if(selectedDates.length===2){document.getElementById('check-in').value=selectedDates[0];document.getElementById('check-out').value=selectedDates[1];calculatePrice();}}
function populatePropertySelect(){document.getElementById('booking-property').innerHTML='<option value="">-- Wybierz --</option>'+properties.map(p=>`<option value="${p.id}">${p.name} - ${p.price} zł/doba</option>`).join('');}
document.getElementById('booking-property')?.addEventListener('change',renderCalendar);
function selectPropertyForBooking(id){showSection('calendar');document.getElementById('booking-property').value=id;renderCalendar();calculatePrice();}
function calculatePrice(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;if(!propId||!checkIn||!checkOut)return;const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));if(nights>0){document.getElementById('price-per-night').textContent=prop.price+' zł';document.getElementById('night-count').textContent=nights;document.getElementById('total-price').textContent=(prop.price*nights)+' zł';}}
['booking-property','check-in','check-out'].forEach(id=>{document.getElementById(id)?.addEventListener('change',calculatePrice);});
async function submitBooking(){if(!currentUser){showToast('Wymagane logowanie','Zaloguj się, aby dokonać rezerwacji','error');showSection('login');return;}const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;const name=document.getElementById('guest-name').value;const email=document.getElementById('guest-email').value;const phone=document.getElementById('guest-phone').value;if(!propId||!checkIn||!checkOut||!name||!email){showToast('Błąd','Wypełnij wszystkie pola','error');return;}const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));const total=prop.price*nights;showToast('Przetwarzanie','FastAPI → PostgreSQL + Redis + Kafka (przez Istio mTLS)...','info');try{const saved=await apiJson('/api/bookings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({property_id:Number(propId),guest_name:name,email:email,phone:phone,guests:prop.guests||1,check_in:checkIn,check_out:checkOut,total_price:Number(total)})});showToast('Sukces!',`Rezerwacja ${saved.id} zapisana`);}catch(e){console.error('POST /api/bookings:',e);showToast('Błąd','Zapis nieudany: '+e.message,'error');return;}document.getElementById('guest-name').value='';document.getElementById('guest-email').value='';document.getElementById('guest-phone').value='';selectedDates=[];await loadBookings();renderCalendar();}
function renderAdmin(){const isAdmin=currentUser&&currentUser.role==='admin';document.getElementById('nav-admin-label').textContent=isAdmin?'Admin':'Moje Rezerwacje';document.querySelector('#admin-section h2').textContent=isAdmin?'Panel Administracyjny':'Moje Rezerwacje';document.getElementById('admin-password-card')?.classList.toggle('hidden',!isAdmin);document.getElementById('stat-bookings').textContent=bookings.length;const revenue=bookings.filter(b=>!b.masked).reduce((sum,b)=>sum+(b.totalPrice||0),0);document.getElementById('stat-revenue').textContent=revenue.toLocaleString()+' zł';document.getElementById('stat-kafka').textContent=Object.values(kafkaTopics).reduce((a,b)=>a+b,0).toLocaleString('pl-PL');['bookings-created','email-invoices','marketing-actions'].forEach(t=>{const el=document.getElementById('topic-'+t);if(el)el.textContent=(kafkaTopics[t]||0).toLocaleString('pl-PL');});document.getElementById('stat-occupancy').textContent=Math.min(95,bookings.length*5)+'%';const tbody=document.getElementById('bookings-table');tbody.innerHTML=bookings.map(b=>{const guest=b.masked?`<i class="fas fa-user-lock text-gray-500 mr-1"></i><span class="text-gray-400">Zastrzeżone</span>`:`${b.guestName}<br><span class="text-xs text-gray-500">${b.email}</span>${b.mine?'<span class="ml-2 text-xs px-2 py-0.5 rounded bg-blue-500/20 text-blue-300">Moja rezerwacja</span>':''}`;const price=b.masked?'<span class="text-gray-500">—</span>':`${(b.totalPrice||0).toLocaleString('pl-PL')} zł`;return `<tr class="border-b border-white/5"><td class="py-4 font-mono text-sm text-blue-400">${b.id}</td><td class="py-4">${b.propertyName}</td><td class="py-4">${guest}</td><td class="py-4 text-sm">${b.checkIn} → ${b.checkOut}<br><span class="text-xs text-gray-500">${b.nights} nocy</span></td><td class="py-4 font-bold">${price}</td><td class="py-4"><span class="px-2 py-1 rounded text-xs ${b.status==='confirmed'?'bg-green-500/20 text-green-400':'bg-yellow-500/20 text-yellow-400'}">${b.status}</span></td></tr>`;}).join('')||'<tr><td colspan="6" class="py-8 text-center text-gray-500">Brak rezerwacji</td></tr>';}
function exportBookings(){const csv='ID,Nieruchomość,Gość,Email,Check-in,Check-out,Nocy,Kwota,Status\n'+bookings.map(b=>`${b.id},${b.propertyName},${b.masked?'ZASTRZEŻONE':b.guestName},${b.masked?'':b.email},${b.checkIn},${b.checkOut},${b.nights},${b.masked?'':b.totalPrice},${b.status}`).join('\n');const blob=new Blob([csv],{type:'text/csv'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='rezerwacje-davtro.csv';a.click();showToast('Eksport','Plik CSV pobrany');}
let authMode='login';
function switchAuthTab(mode){authMode=mode;document.getElementById('tab-login').className='flex-1 py-2 rounded-lg font-semibold '+(mode==='login'?'bg-blue-600':'bg-white/10');document.getElementById('tab-register').className='flex-1 py-2 rounded-lg font-semibold '+(mode==='register'?'bg-blue-600':'bg-white/10');document.getElementById('register-fields').classList.toggle('hidden',mode!=='register');document.getElementById('auth-submit').textContent=mode==='login'?'Zaloguj się':'Zarejestruj się i zaloguj';}
async function submitAuth(){const username=document.getElementById('auth-username').value.trim();const password=document.getElementById('auth-password').value;if(!username||!password){showToast('Błąd','Podaj login i hasło','error');return;}const body={username,password};if(authMode==='register'){body.full_name=document.getElementById('auth-fullname').value.trim()||null;body.email=document.getElementById('auth-email').value.trim()||null;}try{const res=await apiJson('/api/auth/'+(authMode==='login'?'login':'register'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});setSession(res.token,res.user);showToast(authMode==='login'?'Zalogowano':'Konto utworzone','Witaj, '+res.user.username+'!');showSection('calendar');}catch(e){showToast('Błąd','Autoryzacja nieudana: '+e.message,'error');}}
function setSession(token,user){authToken=token;currentUser=user;if(token)localStorage.setItem('davtro_token',token);else localStorage.removeItem('davtro_token');updateNav();if(user){document.getElementById('guest-name').value=user.full_name||'';document.getElementById('guest-email').value=user.email||'';}}
function updateNav(){const logged=!!currentUser;document.getElementById('nav-login').classList.toggle('hidden',logged);document.getElementById('nav-user').classList.toggle('hidden',!logged);document.getElementById('nav-user').classList.toggle('flex',logged);document.getElementById('nav-username').textContent=logged?(currentUser.username+(currentUser.role==='admin'?' (admin)':'')):'';}
function renderLoginSection(){document.getElementById('password-change').classList.toggle('hidden',!currentUser);}
async function changePassword(){if(!currentUser){showToast('Błąd','Najpierw się zaloguj','error');return;}const cur=document.getElementById('pw-current').value;const neu=document.getElementById('pw-new').value;if(!cur||!neu){showToast('Błąd','Wypełnij oba pola','error');return;}try{const res=await apiJson('/api/auth/change-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({current_password:cur,new_password:neu})});document.getElementById('pw-current').value='';document.getElementById('pw-new').value='';showToast('Gotowe',res.message||'Hasło zmienione');}catch(e){showToast('Błąd','Zmiana hasła nieudana: '+e.message,'error');}}
async function adminSetPassword(){const username=document.getElementById('adm-username').value.trim();const neu=document.getElementById('adm-newpass').value;if(!username||!neu){showToast('Błąd','Podaj login i nowe hasło','error');return;}try{const res=await apiJson('/api/auth/admin/set-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,new_password:neu})});document.getElementById('adm-username').value='';document.getElementById('adm-newpass').value='';showToast('Gotowe',res.message||'Hasło ustawione');}catch(e){showToast('Błąd','Nie udało się: '+e.message,'error');}}
async function logout(){try{await apiJson('/api/auth/logout',{method:'POST'});}catch(e){}setSession(null,null);bookings=[];showToast('Wylogowano','Sesja zakończona','info');showSection('home');}
async function restoreSession(){if(!authToken)return;try{currentUser=await apiJson('/api/auth/me');updateNav();document.getElementById('guest-name').value=currentUser.full_name||'';document.getElementById('guest-email').value=currentUser.email||'';}catch(e){setSession(null,null);}}
restoreSession().finally(()=>loadProperties().then(()=>{renderFeatured();showSection('home');}));
</script>
</body>
</html>
HTMLEOF

cat > ${PROJECT_NAME}/frontend/Dockerfile << 'EOF'
FROM docker.io/nginxinc/nginx-unprivileged:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
EOF

cat > ${PROJECT_NAME}/frontend/nginx.conf << 'EOF'
server {
    listen       8080;
    server_name  _;
    root  /usr/share/nginx/html;
    index index.html;
    location / { try_files $uri $uri/ /index.html; }
    # FastAPI – ruch do sidecara Envoy (localhost:15001) -> Istio mTLS do usługi
    location /api/ {
        proxy_pass         http://fastapi-web-app-svc:80;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout    30s;
    }
    location = /kafka-metrics {
        proxy_pass       http://kafka-exporter:9308/metrics;
        proxy_set_header Host $host;
        proxy_connect_timeout 3s;
        proxy_read_timeout    10s;
    }
}
EOF

# ============================================
# FASTAPI BACKEND (bez SSL – Istio sidecar robi mTLS)
# ============================================
cat > ${PROJECT_NAME}/backend-fastapi/requirements.txt << 'EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
asyncpg==0.29.0
sqlalchemy==2.0.35
psycopg2-binary==2.9.9
redis==5.0.8
kafka-python==2.0.2
confluent-kafka==2.5.3
pydantic[email]==2.9.2
python-multipart==0.0.9
jinja2==3.1.4
prometheus-fastapi-instrumentator==7.0.0
hvac==2.3.0
requests==2.32.3
EOF

cat > ${PROJECT_NAME}/backend-fastapi/Dockerfile << 'EOF'
FROM python:3.11-slim
RUN groupadd -g 1000 appuser && useradd -u 1000 -g appuser appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
RUN chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
CMD ["python","-m","uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]
EOF

cat > ${PROJECT_NAME}/Dockerfile.consumer << 'EOF'
FROM python:3.12-slim
RUN groupadd -g 1000 appuser && useradd -u 1000 -g appuser appuser
WORKDIR /srv
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
COPY backend-fastapi/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY backend-fastapi/app ./app
RUN chown -R appuser:appuser /srv
USER appuser
CMD ["python", "-m", "app.consumer"]
EOF

mkdir -p ${PROJECT_NAME}/backend-fastapi/app
cat > ${PROJECT_NAME}/backend-fastapi/app/__init__.py << 'EOF'

EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/kafka_producer.py << 'EOF'
"""
KROK 11 (Istio): producent Kafka BEZ SSL/mTLS.
Ruch do brokera jest szyfrowany przez sidecar Envoy (Istio mTLS, SPIFFE).
Aplikacja laczy sie z kafka-kraft:9092 jako PLAINTEXT (localhost -> sidecar).
"""
import json
import os
from confluent_kafka import Producer

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
_producer = None


def get_producer():
    global _producer
    if _producer is None:
        _producer = Producer({
            "bootstrap.servers": KAFKA_BOOTSTRAP,
            # ISTIO: brak security.protocol=SSL, brak ssl.*
            # Sidecar Envoy transparentnie szyfruje TCP do brokera.
        })
    return _producer


def publish_event(topic: str, event: dict):
    producer = get_producer()
    producer.produce(topic, json.dumps(event).encode("utf-8"))
    producer.flush(5)
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/transit_client.py << 'EOF'
#!/usr/bin/env python3
"""
KROK 4 (Transit PII): Vault Transit Engine client.
Szyfruje/deszyfruje wrazliwe dane (PII) przed zapisem do PostgreSQL.
To NIE jest zastapione przez Istio - Istio chroni ruch, Transit chroni dane w spoczynku.
"""
import base64
import logging
import os
import time
from typing import Dict, Optional, Tuple
import requests

logger = logging.getLogger(__name__)
TOKEN_TTL_SECONDS = 3000
DEFAULT_VAULT_CA_FILE = "/etc/vault-tls/ca.crt"
DEFAULT_VAULT_TIMEOUT = 30


def vault_tls_config() -> Tuple[str, object]:
    scheme = os.environ.get("VAULT_TRANSIT_SCHEME", "https")
    addr = os.environ.get("VAULT_TRANSIT_ADDR") or f"{scheme}://vault.davtro02.svc.cluster.local:8203"
    ca_file = os.environ.get("VAULT_TRANSIT_CA_FILE", DEFAULT_VAULT_CA_FILE)
    if ca_file and os.path.exists(ca_file):
        return addr, ca_file
    if scheme == "https":
        logger.warning("Vault: brak pliku CA '%s' - uzywam systemowego store CA", ca_file)
        return addr, True
    return addr, False


class VaultTokenProvider:
    def __init__(self, vault_addr=None, verify=None, timeout=None):
        default_addr, default_verify = vault_tls_config()
        self.vault_addr = vault_addr or default_addr
        self.verify = default_verify if verify is None else verify
        self.auth_role = os.environ.get("VAULT_TRANSIT_AUTH_ROLE", "davtro-transit")
        self.timeout = timeout or int(os.environ.get("VAULT_TRANSIT_TIMEOUT", DEFAULT_VAULT_TIMEOUT))
        self._token = None
        self._token_expiry = 0.0

    def get_token(self, renew=False):
        if self._token and not renew and time.time() < self._token_expiry:
            return self._token
        with open("/var/run/secrets/kubernetes.io/serviceaccount/token") as f:
            sa_token = f.read().strip()
        url = f"{self.vault_addr}/v1/auth/kubernetes/login"
        payload = {"jwt": sa_token, "role": self.auth_role}
        resp = requests.post(url, json=payload, timeout=self.timeout, verify=self.verify)
        resp.raise_for_status()
        auth = resp.json()["auth"]
        self._token = auth["client_token"]
        lease = int(auth.get("lease_duration") or 3600)
        self._token_expiry = time.time() + max(60, min(lease - 60, TOKEN_TTL_SECONDS))
        return self._token


class TransitClient:
    def __init__(self, key_name=None):
        self.vault_addr, self.verify = vault_tls_config()
        self.key_name = key_name or os.environ.get("VAULT_TRANSIT_KEY", "davtro-app")
        self.timeout = int(os.environ.get("VAULT_TRANSIT_TIMEOUT", DEFAULT_VAULT_TIMEOUT))
        self.token_provider = VaultTokenProvider(self.vault_addr, self.verify)
        self._session = requests.Session()

    def _request(self, path, payload):
        url = f"{self.vault_addr}/v1/{path}"
        for attempt in (1, 2):
            token = self.token_provider.get_token(renew=(attempt == 2))
            resp = self._session.post(url, json=payload,
                                      headers={"X-Vault-Token": token},
                                      timeout=self.timeout, verify=self.verify)
            if resp.status_code == 403 and attempt == 1:
                continue
            resp.raise_for_status()
            return resp.json()["data"]
        raise RuntimeError("Vault transit: nieudana autoryzacja")

    def encrypt(self, plaintext):
        b64 = base64.b64encode(str(plaintext).encode()).decode()
        data = self._request(f"transit/encrypt/{self.key_name}", {"plaintext": b64})
        return data["ciphertext"]

    def decrypt(self, ciphertext):
        data = self._request(f"transit/decrypt/{self.key_name}", {"ciphertext": ciphertext})
        return base64.b64decode(data["plaintext"]).decode()


_transit_client = None


def get_transit_client():
    global _transit_client
    if _transit_client is None:
        _transit_client = TransitClient()
    return _transit_client


def encrypt(plaintext):
    return get_transit_client().encrypt(plaintext)


def decrypt(ciphertext):
    return get_transit_client().decrypt(ciphertext)
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/auth.py << 'EOF'
import hashlib, hmac, secrets
PBKDF2_ITERATIONS = 260_000
SALT_BYTES = 16
SESSION_TOKEN_BYTES = 32
SESSION_TTL_SECONDS = 86_400


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(SALT_BYTES)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, iterations, salt_hex, hash_hex = stored.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), int(iterations))
        return hmac.compare_digest(digest.hex(), hash_hex)
    except (ValueError, TypeError):
        return False


def new_session_token() -> str:
    return secrets.token_urlsafe(SESSION_TOKEN_BYTES)


def generate_random_password(length: int = 24) -> str:
    return secrets.token_urlsafe(max(16, min(length, 64)))
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/email_sender.py << 'EOF'
import os
import smtplib
from email.mime.text import MIMEText

SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
FROM_EMAIL = os.getenv("FROM_EMAIL", "rezerwacje@davtro.pl")


def _send(to_email: str, subject: str, body: str):
    if not SMTP_HOST:
        print(f"[DEV] Email do {to_email}: {subject}\n{body}")
        return
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = FROM_EMAIL
    msg["To"] = to_email
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.sendmail(FROM_EMAIL, [to_email], msg.as_string())


def send_confirmation_email(to_email: str, guest_name: str, event: dict):
    subject = f"Potwierdzenie rezerwacji nr {event['booking_id']}"
    body = (f"Cześć {guest_name},\n\n"
            f"Twoja rezerwacja ({event['date_from']} - {event['date_to']}) została potwierdzona.\n"
            f"W załączeniu (proforma) prosimy o dokonanie płatności przed przyjazdem.\n\n"
            f"Pozdrawiamy,\nDavtro Apartments")
    _send(to_email, subject, body)


def send_marketing_email(to_email: str, guest_name: str):
    subject = "Sprawdź nasze najnowsze oferty!"
    body = f"Cześć {guest_name}, mamy dla Ciebie nowe promocje na pobyty krótkoterminowe."
    _send(to_email, subject, body)
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/db.py << 'EOF'
import os
import threading
from sqlalchemy import create_engine, Column, Integer, String, Numeric, Date, Boolean, DateTime, func
from sqlalchemy.orm import declarative_base, sessionmaker

DB_HOST = os.getenv("DB_HOST", "postgres-clusterip")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")
DB_USER_FILE = os.getenv("DB_USER_FILE")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE")
DATABASE_URL = os.getenv("DATABASE_URL")


def _read_file(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return None


def current_creds():
    if DATABASE_URL:
        return DATABASE_URL
    user = (_read_file(DB_USER_FILE) if DB_USER_FILE else None) or os.getenv("DB_USER")
    password = (_read_file(DB_PASSWORD_FILE) if DB_PASSWORD_FILE else None) or os.getenv("DB_PASSWORD")
    if not user or not password:
        raise RuntimeError("Brak credsy DB")
    return f"postgresql://{user}:{password}@{DB_HOST}:{DB_PORT}/{DB_NAME}"


_engine_cache = {"key": None, "engine": None}
_cache_lock = threading.Lock()


def get_engine():
    url = current_creds()
    with _cache_lock:
        if _engine_cache["key"] != url:
            old = _engine_cache["engine"]
            _engine_cache["engine"] = create_engine(url, pool_pre_ping=True, pool_recycle=300)
            _engine_cache["key"] = url
            if old is not None:
                old.dispose()
        return _engine_cache["engine"]


def get_session():
    return sessionmaker(bind=get_engine(), autoflush=False, autocommit=False)()


SessionLocal = get_session
Base = declarative_base()


class Apartment(Base):
    __tablename__ = "apartments"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    description = Column(String)
    price_per_night = Column(Numeric(10, 2), nullable=False)


class Booking(Base):
    __tablename__ = "bookings"
    id = Column(Integer, primary_key=True)
    apartment_id = Column(Integer, nullable=False)
    date_from = Column(Date, nullable=False)
    date_to = Column(Date, nullable=False)
    guest_name = Column(String, nullable=False)
    guest_email = Column(String, nullable=False)
    marketing_consent = Column(Boolean, default=False)
    status = Column(String, default="pending")
    invoice_sent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())


def init_db():
    engine = get_engine()
    Base.metadata.create_all(bind=engine)
    session = get_session()
    if session.query(Apartment).count() == 0:
        session.add_all([
            Apartment(name="Apartament Centrum", description="2 pokoje, blisko rynku", price_per_night=250),
            Apartment(name="Apartament Panoramiczny", description="Widok na miasto", price_per_night=320),
            Apartment(name="Studio Kompakt", description="Idealne dla pary", price_per_night=180),
        ])
        session.commit()
    session.close()
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/main.py << 'PYEOF'
from fastapi import FastAPI, HTTPException, BackgroundTasks, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import List, Optional
import asyncpg
import redis.asyncio as aioredis
import asyncio
import json
import os
from datetime import datetime, date
from .kafka_producer import get_producer, publish_event
import uvicorn

from .auth import hash_password, verify_password, new_session_token, SESSION_TTL_SECONDS, generate_random_password

try:
    from .transit_client import decrypt as transit_decrypt
    from .transit_client import encrypt as transit_encrypt
    _TRANSIT_IMPORTED = True
except Exception as _transit_exc:
    transit_encrypt = None
    transit_decrypt = None
    _TRANSIT_IMPORTED = False
    print("transit_client niedostepny:", _transit_exc)

TRANSIT_ENABLED = os.getenv("VAULT_TRANSIT_ENABLED", "true").lower() in ("1", "true", "yes")
_TRANSIT_PREFIX = "vault:v"

app = FastAPI(title="DavTro Rentals API (Istio Edition)", version="2.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

DB_HOST = os.getenv("DB_HOST", "postgres-clusterip")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")
DB_USER_FILE = os.getenv("DB_USER_FILE")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")

db_pool = None
redis_pool = None
kafka_producer = None


def transit_ready():
    return _TRANSIT_IMPORTED and TRANSIT_ENABLED


def encrypt_pii(value):
    if value is None or not transit_ready():
        return value
    try:
        return transit_encrypt(str(value))
    except Exception as exc:
        print("encrypt_pii error:", exc)
        return value


def decrypt_pii(value):
    if not isinstance(value, str) or not value.startswith(_TRANSIT_PREFIX):
        return value
    if not transit_ready():
        return value
    try:
        return transit_decrypt(value)
    except Exception as exc:
        print("decrypt_pii error:", exc)
        return value


def _read_creds_file(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return None


def db_creds():
    user = (_read_creds_file(DB_USER_FILE) if DB_USER_FILE else None) or os.getenv("DB_USER")
    password = (_read_creds_file(DB_PASSWORD_FILE) if DB_PASSWORD_FILE else None) or os.getenv("DB_PASSWORD")
    if not user or not password:
        raise RuntimeError("Brak credsy DB")
    return user, password


def admin_password():
    file_path = os.getenv("ADMIN_PASSWORD_FILE")
    from_file = _read_creds_file(file_path) if file_path else None
    return from_file or os.getenv("ADMIN_PASSWORD") or None


def admin_password_or_generated():
    pwd = admin_password()
    if pwd is not None:
        return pwd
    pwd = generate_random_password()
    print(f"init_db: brak ADMIN_PASSWORD z Vaulta - wygenerowano losowe haslo admina: {pwd}")
    return pwd


async def create_db_pool(user, password):
    return await asyncpg.create_pool(host=DB_HOST, port=DB_PORT, database=DB_NAME,
                                     user=user, password=password, min_size=5, max_size=20)


async def watch_db_creds():
    global db_pool
    last = db_creds()
    while True:
        await asyncio.sleep(30)
        try:
            current = db_creds()
            if current != last:
                old_pool = db_pool
                db_pool = await create_db_pool(*current)
                last = current
                if old_pool:
                    await old_pool.close()
                print("db_pool: przelaczono na nowe credsy z Vault")
        except Exception as exc:
            print("watch_db_creds error:", exc)


class BookingCreate(BaseModel):
    property_id: int
    guest_name: str
    email: EmailStr
    phone: Optional[str] = None
    guests: int = 1
    check_in: date
    check_out: date
    total_price: float


class BookingResponse(BaseModel):
    id: str
    property_id: int
    property_name: str
    guest_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    check_in: str
    check_out: str
    total_price: Optional[float] = None
    status: str
    created_at: str
    masked: bool = False
    mine: bool = False


class AuthUser(BaseModel):
    id: int
    username: str
    role: str
    full_name: Optional[str] = None
    email: Optional[str] = None


class AuthRequest(BaseModel):
    username: str
    password: str


class RegisterRequest(AuthRequest):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class AdminSetPasswordRequest(BaseModel):
    username: str
    new_password: str


@app.on_event("startup")
async def startup():
    global db_pool, redis_pool, kafka_producer
    user, password = db_creds()
    db_pool = await create_db_pool(user, password)
    redis_pool = aioredis.from_url(f"redis://{REDIS_HOST}:{REDIS_PORT}", decode_responses=True)
    kafka_producer = get_producer()
    asyncio.create_task(watch_db_creds())
    await init_db()


@app.on_event("shutdown")
async def shutdown():
    if db_pool: await db_pool.close()
    if redis_pool: await redis_pool.close()
    if kafka_producer: kafka_producer.flush(5)


async def init_db():
    async with db_pool.acquire() as conn:
        await conn.execute('CREATE TABLE IF NOT EXISTS properties (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, location VARCHAR(100), price DECIMAL(10,2), guests INT DEFAULT 2, description TEXT, amenities JSONB DEFAULT \'[]\', created_at TIMESTAMP DEFAULT NOW())')
        await conn.execute('CREATE TABLE IF NOT EXISTS bookings (id VARCHAR(50) PRIMARY KEY, property_id INT REFERENCES properties(id), guest_name VARCHAR(255), email VARCHAR(255), phone VARCHAR(255), guests INT, user_id INT, username VARCHAR(100), check_in DATE, check_out DATE, nights INT, total_price DECIMAL(10,2), status VARCHAR(50) DEFAULT \'confirmed\', pipeline VARCHAR(100) DEFAULT \'Istio-mTLS -> Redis -> Kafka -> PostgreSQL\', created_at TIMESTAMP DEFAULT NOW())')
        try:
            await conn.execute("ALTER TABLE bookings ALTER COLUMN phone TYPE VARCHAR(255)")
        except Exception as exc:
            print("init_db: pomijam ALTER bookings.phone:", exc)
        await conn.execute("""CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY, username VARCHAR(100) UNIQUE NOT NULL,
            password_hash TEXT NOT NULL, role VARCHAR(20) NOT NULL DEFAULT 'user',
            full_name VARCHAR(255), email VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW())""")
        for ddl in ("ALTER TABLE bookings ADD COLUMN IF NOT EXISTS user_id INT",
                    "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS username VARCHAR(100)"):
            try:
                await conn.execute(ddl)
            except Exception as exc:
                print("init_db: pomijam", ddl, ":", exc)
        count = await conn.fetchval("SELECT COUNT(*) FROM properties")
        if count == 0:
            await conn.execute("""INSERT INTO properties (id, name, location, price, guests, description, amenities) VALUES
                (1, 'Apartament Premium - Warszawa', 'warsaw', 450, 4, 'Luksusowy apartament w centrum', '["WiFi","Klimatyzacja","Balkon","Parking"]'),
                (2, 'Studio Modern - Krakow', 'krakow', 320, 2, 'Stylowe studio obok Rynku', '["WiFi","Smart TV","Kuchnia"]'),
                (3, 'Villa nad Morzem - Gdansk', 'gdansk', 680, 6, 'Willa 200m od plazy', '["WiFi","Ogrodek","Grill","Parking"]'),
                (4, 'Loft Industrial - Wroclaw', 'wroclaw', 280, 3, 'Industrialny loft', '["WiFi","Projektor","Klimatyzacja"]'),
                (5, 'Penthouse View - Warszawa', 'warsaw', 850, 4, 'Ekskluzywny penthouse', '["WiFi","Basen","Silownia","Concierge"]'),
                (6, 'Apartament Royal - Krakow', 'krakow', 390, 4, 'Elegancki apartament w Kazimierzu', '["WiFi","Klimatyzacja","Balkon"]')
                ON CONFLICT DO NOTHING""")
        admin_user = os.getenv("ADMIN_USERNAME", "admin")
        admin_pass = admin_password_or_generated()
        if await conn.fetchval("SELECT 1 FROM users WHERE username=$1", admin_user) is None:
            await conn.execute(
                "INSERT INTO users (username, password_hash, role) VALUES ($1,$2,'admin') ON CONFLICT (username) DO NOTHING",
                admin_user, hash_password(admin_pass))
            print(f"init_db: utworzono konto admina '{admin_user}'")


@app.get("/api/health")
async def health():
    redis_ok = await redis_pool.ping()
    async with db_pool.acquire() as conn:
        db_ok = await conn.fetchval("SELECT 1")
    return {"status": "healthy", "database": db_ok == 1, "redis": redis_ok,
            "kafka": kafka_producer is not None, "transit": transit_ready(),
            "mtls": "istio-sidecar"}


@app.get("/api/properties")
async def get_properties():
    cache_key = "properties:all"
    cached = await redis_pool.get(cache_key)
    if cached: return json.loads(cached)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM properties ORDER BY id")
    properties = [{"id": r["id"], "name": r["name"], "location": r["location"], "price": float(r["price"]),
                   "guests": r["guests"], "description": r["description"],
                   "amenities": json.loads(r["amenities"])} for r in rows]
    await redis_pool.setex(cache_key, 300, json.dumps(properties))
    return properties


SESSION_KEY_PREFIX = "session:"
BOOKINGS_HAS_USER_ID = True
BOOKINGS_HAS_USERNAME = True


async def get_current_user(request: Request) -> Optional[AuthUser]:
    auth_header = request.headers.get("authorization") or ""
    if not auth_header.lower().startswith("bearer "):
        return None
    token = auth_header[7:].strip()
    if not token:
        return None
    raw = await redis_pool.get(SESSION_KEY_PREFIX + token)
    if not raw:
        return None
    data = json.loads(raw)
    return AuthUser(id=data["id"], username=data["username"], role=data["role"],
                    full_name=data.get("full_name"), email=data.get("email"))


async def require_user(request: Request) -> AuthUser:
    user = await get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Wymagane zalogowanie")
    return user


def is_admin(user: Optional[AuthUser]) -> bool:
    return user is not None and user.role == "admin"


def owns_booking(user: Optional[AuthUser], row_user_id) -> bool:
    if user is None:
        return False
    if user.role == "admin":
        return True
    return row_user_id is not None and int(row_user_id) == int(user.id)


MASKED_GUEST_NAME = "Zastrzeżone (dane gościa ukryte)"


@app.post("/api/auth/register")
async def register_user(payload: RegisterRequest):
    username = payload.username.strip()
    if len(username) < 3 or len(payload.password) < 6:
        raise HTTPException(status_code=400, detail="Login min. 3 znaki, haslo min. 6 znakow")
    full_name = encrypt_pii(payload.full_name) if payload.full_name else None
    email = encrypt_pii(payload.email) if payload.email else None
    async with db_pool.acquire() as conn:
        exists = await conn.fetchval("SELECT 1 FROM users WHERE username=$1", username)
        if exists:
            raise HTTPException(status_code=409, detail="Ten login jest juz zajety")
        user_id = await conn.fetchval(
            """INSERT INTO users (username, password_hash, role, full_name, email)
               VALUES ($1,$2,'user',$3,$4) RETURNING id""",
            username, hash_password(payload.password), full_name, email)
    token = new_session_token()
    await redis_pool.setex(SESSION_KEY_PREFIX + token, SESSION_TTL_SECONDS,
                           json.dumps({"id": user_id, "username": username, "role": "user",
                                       "full_name": decrypt_pii(full_name) if full_name else None,
                                       "email": decrypt_pii(email) if email else None}))
    return {"token": token, "user": AuthUser(id=user_id, username=username, role="user",
                                             full_name=decrypt_pii(full_name) if full_name else None,
                                             email=decrypt_pii(email) if email else None)}


@app.post("/api/auth/login")
async def login_user(payload: AuthRequest):
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM users WHERE username=$1", payload.username.strip())
        if row is None and payload.username.strip() == os.getenv("ADMIN_USERNAME", "admin"):
            admin_user = payload.username.strip()
            await conn.execute(
                "INSERT INTO users (username, password_hash, role) VALUES ($1,$2,'admin') ON CONFLICT (username) DO NOTHING",
                admin_user, hash_password(admin_password_or_generated()))
            row = await conn.fetchrow("SELECT * FROM users WHERE username=$1", admin_user)
    if row is None or not verify_password(payload.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Nieprawidlowy login lub haslo")
    full_name = decrypt_pii(row["full_name"]) if row["full_name"] else None
    email = decrypt_pii(row["email"]) if row["email"] else None
    token = new_session_token()
    await redis_pool.setex(SESSION_KEY_PREFIX + token, SESSION_TTL_SECONDS,
                           json.dumps({"id": row["id"], "username": row["username"],
                                       "role": row["role"], "full_name": full_name, "email": email}))
    return {"token": token, "user": AuthUser(id=row["id"], username=row["username"],
                                             role=row["role"], full_name=full_name, email=email)}


@app.post("/api/auth/logout")
async def logout_user(request: Request):
    auth_header = request.headers.get("authorization") or ""
    if auth_header.lower().startswith("bearer "):
        await redis_pool.delete(SESSION_KEY_PREFIX + auth_header[7:].strip())
    return {"ok": True}


@app.get("/api/auth/me")
async def me(request: Request):
    user = await get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Brak aktywnej sesji")
    return user


@app.post("/api/auth/change-password")
async def change_password(payload: ChangePasswordRequest, request: Request):
    user = await require_user(request)
    if len(payload.new_password) < 6:
        raise HTTPException(status_code=400, detail="Nowe haslo musi miec min. 6 znakow")
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT password_hash FROM users WHERE id=$1", user.id)
        if row is None or not verify_password(payload.current_password, row["password_hash"]):
            raise HTTPException(status_code=401, detail="Aktualne haslo jest nieprawidlowe")
        await conn.execute("UPDATE users SET password_hash=$1 WHERE id=$2",
                           hash_password(payload.new_password), user.id)
    return {"ok": True, "message": "Haslo zmienione"}


@app.post("/api/auth/admin/set-password")
async def admin_set_password(payload: AdminSetPasswordRequest, request: Request):
    user = await require_user(request)
    if not is_admin(user):
        raise HTTPException(status_code=403, detail="Tylko administrator moze zmieniac cudze hasla")
    if len(payload.new_password) < 6:
        raise HTTPException(status_code=400, detail="Nowe haslo musi miec min. 6 znakow")
    async with db_pool.acquire() as conn:
        found = await conn.fetchval("SELECT 1 FROM users WHERE username=$1", payload.username.strip())
        if found is None:
            raise HTTPException(status_code=404, detail="Nie ma takiego uzytkownika")
        await conn.execute("UPDATE users SET password_hash=$1 WHERE username=$2",
                           hash_password(payload.new_password), payload.username.strip())
    return {"ok": True, "message": f"Haslo uzytkownika {payload.username.strip()} zostalo zmienione"}


@app.post("/api/bookings")
async def create_booking(booking: BookingCreate, background_tasks: BackgroundTasks, request: Request):
    user = await require_user(request)
    booking_id = f"BK-{datetime.now().strftime('%Y%m%d%H%M%S')}-{booking.property_id}"
    nights = (booking.check_out - booking.check_in).days
    cache_key = f"booking:{booking_id}"
    booking_data = booking.model_dump(mode="json")
    booking_data.update({"id": booking_id, "nights": nights, "status": "pending"})
    async with db_pool.acquire() as conn:
        if BOOKINGS_HAS_USER_ID and BOOKINGS_HAS_USERNAME:
            await conn.execute(
                """INSERT INTO bookings (id, property_id, guest_name, email, phone, guests, user_id, username,
                       check_in, check_out, nights, total_price, status)
                   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
                   ON CONFLICT (id) DO NOTHING""",
                booking_id, booking.property_id,
                encrypt_pii(booking.guest_name), encrypt_pii(booking.email), encrypt_pii(booking.phone),
                booking.guests, user.id, user.username, booking.check_in, booking.check_out, nights,
                booking.total_price, "pending")
        else:
            await conn.execute(
                """INSERT INTO bookings (id, property_id, guest_name, email, phone, guests,
                       check_in, check_out, nights, total_price, status)
                   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
                   ON CONFLICT (id) DO NOTHING""",
                booking_id, booking.property_id,
                encrypt_pii(booking.guest_name), encrypt_pii(booking.email), encrypt_pii(booking.phone),
                booking.guests, booking.check_in, booking.check_out, nights,
                booking.total_price, "pending")
    await redis_pool.setex(cache_key, 3600, json.dumps(booking_data))
    publish_event("bookings-created", {"event": "booking_created", "booking_id": booking_id,
                                       "property_id": booking.property_id, "guest_name": booking.guest_name,
                                       "email": booking.email, "phone": booking.phone,
                                       "check_in": str(booking.check_in), "check_out": str(booking.check_out),
                                       "nights": nights, "total_price": float(booking.total_price),
                                       "timestamp": datetime.now().isoformat()})
    publish_event("email-invoices", {"event": "invoice_request", "booking_id": booking_id,
                                     "email": booking.email, "guest_name": booking.guest_name,
                                     "total_price": float(booking.total_price),
                                     "property_id": booking.property_id,
                                     "check_in": str(booking.check_in), "check_out": str(booking.check_out)})
    publish_event("marketing-actions", {"event": "new_booking", "property_id": booking.property_id,
                                        "guest_email": booking.email, "guest_name": booking.guest_name,
                                        "booking_value": float(booking.total_price),
                                        "timestamp": datetime.now().isoformat()})
    return BookingResponse(id=booking_id, property_id=booking.property_id, property_name="",
                           guest_name=booking.guest_name, email=booking.email,
                           check_in=str(booking.check_in), check_out=str(booking.check_out),
                           total_price=booking.total_price, status="pending",
                           created_at=datetime.now().isoformat())


@app.get("/api/bookings")
async def get_bookings(request: Request, property_id: Optional[int] = None):
    user = await get_current_user(request)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT b.*, p.name as property_name FROM bookings b JOIN properties p ON b.property_id = p.id WHERE ($1::int IS NULL OR b.property_id = $1::int) ORDER BY b.created_at DESC",
            property_id)
    result = []
    for r in rows:
        is_own = user is not None and r.get("user_id") is not None and int(r.get("user_id")) == int(user.id)
        if owns_booking(user, r.get("user_id")):
            result.append(BookingResponse(
                id=r["id"], property_id=r["property_id"], property_name=r["property_name"],
                guest_name=decrypt_pii(r["guest_name"]), email=decrypt_pii(r["email"]),
                phone=decrypt_pii(r["phone"]) if r["phone"] else None,
                check_in=str(r["check_in"]), check_out=str(r["check_out"]),
                total_price=float(r["total_price"]), status=r["status"],
                created_at=str(r["created_at"]), masked=False, mine=is_own and user.role != "admin"))
        else:
            result.append(BookingResponse(
                id=r["id"], property_id=r["property_id"], property_name=r["property_name"],
                guest_name=MASKED_GUEST_NAME, email=None, phone=None,
                check_in=str(r["check_in"]), check_out=str(r["check_out"]),
                total_price=None, status=r["status"],
                created_at=str(r["created_at"]), masked=True, mine=False))
    return result


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
PYEOF

cat > ${PROJECT_NAME}/backend-fastapi/app/consumer.py << 'EOF'
"""
message-processor: konsument Kafka (Istio mTLS przez sidecar).
Czyta z bookings-created i marketing-actions, wysyla e-mail, aktualizuje status w DB.
"""
import json
import os
import redis
from confluent_kafka import Consumer
from .db import SessionLocal, Booking
from .email_sender import send_confirmation_email, send_marketing_email

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def handle_booking_event(event: dict):
    dedup_key = f"processed:{event.get('event_id', event.get('booking_id', 'unknown'))}"
    if redis_client.get(dedup_key):
        return
    send_confirmation_email(event.get("email", event.get("guest_email")),
                            event.get("guest_name", "Gosc"), event)
    session = SessionLocal()
    try:
        booking = session.query(Booking).get(event.get("booking_id"))
        if booking:
            booking.status = "confirmed"
            booking.invoice_sent = True
            session.commit()
    finally:
        session.close()
    redis_client.setex(dedup_key, 86400, "1")


def handle_marketing_event(event: dict):
    send_marketing_email(event.get("guest_email", event.get("email")), event.get("guest_name", "Gosc"))


def main():
    # ISTIO: brak security.protocol=SSL, brak ssl.*
    # Sidecar Envoy szyfruje TCP do brokera.
    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": "message-processor",
        "auto.offset.reset": "earliest",
    })
    consumer.subscribe(["bookings-created", "marketing-actions"])
    print("message-processor: nasluchiwanie (Istio mTLS)...")
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print("Kafka error:", msg.error())
                continue
            event = json.loads(msg.value().decode("utf-8"))
            if msg.topic() == "bookings-created":
                handle_booking_event(event)
            elif msg.topic() == "marketing-actions":
                handle_marketing_event(event)
    except KeyboardInterrupt:
        pass
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
EOF

# ============================================
# SPRING BOOT (bez SSL – Istio sidecar)
# ============================================
cat > ${PROJECT_NAME}/java-app/pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.2.0</version><relativePath/></parent>
  <groupId>com.davtro</groupId><artifactId>rental-processor</artifactId><version>1.0.0</version>
  <properties><java.version>17</java.version></properties>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
    <dependency><groupId>org.springframework.kafka</groupId><artifactId>spring-kafka</artifactId></dependency>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-mail</artifactId></dependency>
  </dependencies>
  <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build>
</project>
EOF

cat > ${PROJECT_NAME}/java-app/Dockerfile << 'EOF'
FROM eclipse-temurin:17-jdk-alpine
RUN addgroup -g 1000 appgroup && adduser -u 1000 -G appgroup -D appuser
WORKDIR /app
COPY target/rental-processor-1.0.0.jar app.jar
RUN chown appuser:appgroup app.jar
USER appuser
EXPOSE 8081
ENTRYPOINT ["java","-jar","app.jar"]
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/{model,repository,consumer,service}
cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/RentalProcessorApplication.java << 'EOF'
package com.davtro.rental;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.kafka.annotation.EnableKafka;
@SpringBootApplication @EnableKafka
public class RentalProcessorApplication {
    public static void main(String[] args) { SpringApplication.run(RentalProcessorApplication.class, args); }
}
EOF

cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/model/Booking.java << 'EOF'
package com.davtro.rental.model;
import jakarta.persistence.*;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
@Entity @Table(name = "bookings") @Data
public class Booking {
    @Id private String id;
    private Integer propertyId;
    private String guestName;
    private String email;
    private String phone;
    private Integer guests;
    private LocalDate checkIn;
    private LocalDate checkOut;
    private Integer nights;
    private BigDecimal totalPrice;
    private String status;
    private String pipeline;
    private LocalDateTime createdAt;
}
EOF

cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/repository/BookingRepository.java << 'EOF'
package com.davtro.rental.repository;
import com.davtro.rental.model.Booking;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
@Repository
public interface BookingRepository extends JpaRepository<Booking, String> {}
EOF

cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/consumer/BookingConsumer.java << 'EOF'
package com.davtro.rental.consumer;
import com.davtro.rental.model.Booking;
import com.davtro.rental.repository.BookingRepository;
import com.davtro.rental.service.EmailService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
@Component @RequiredArgsConstructor @Slf4j
public class BookingConsumer {
    private final BookingRepository bookingRepository;
    private final EmailService emailService;
    private final ObjectMapper objectMapper;
    @KafkaListener(topics = "bookings-created", groupId = "spring-app-group")
    public void consumeBooking(String message) {
        try {
            JsonNode json = objectMapper.readTree(message);
            log.info("Received booking: {}", json.get("booking_id").asText());
            Booking booking = new Booking();
            booking.setId(json.get("booking_id").asText());
            booking.setPropertyId(json.get("property_id").asInt());
            booking.setGuestName(json.get("guest_name").asText());
            booking.setEmail(json.get("email").asText());
            booking.setPhone(json.has("phone") ? json.get("phone").asText() : null);
            booking.setGuests(json.has("guests") ? json.get("guests").asInt() : 2);
            booking.setCheckIn(LocalDate.parse(json.get("check_in").asText()));
            booking.setCheckOut(LocalDate.parse(json.get("check_out").asText()));
            booking.setNights(json.get("nights").asInt());
            booking.setTotalPrice(new BigDecimal(json.get("total_price").asText()));
            booking.setStatus("confirmed");
            booking.setPipeline("Istio-mTLS -> Redis -> Kafka -> PostgreSQL");
            booking.setCreatedAt(LocalDateTime.now());
            bookingRepository.save(booking);
            log.info("Booking saved: {}", booking.getId());
        } catch (Exception e) { log.error("Error: {}", e.getMessage()); }
    }
    @KafkaListener(topics = "email-invoices", groupId = "spring-app-group")
    public void consumeInvoice(String message) {
        try {
            JsonNode json = objectMapper.readTree(message);
            emailService.sendProformaInvoice(json.get("email").asText(), json.get("guest_name").asText(),
                    json.get("booking_id").asText(), new BigDecimal(json.get("total_price").asText()));
        } catch (Exception e) { log.error("Error sending invoice: {}", e.getMessage()); }
    }
}
EOF

cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/service/EmailService.java << 'EOF'
package com.davtro.rental.service;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import java.math.BigDecimal;
@Service @RequiredArgsConstructor @Slf4j
public class EmailService {
    private final JavaMailSender mailSender;
    public void sendProformaInvoice(String to, String guestName, String bookingId, BigDecimal total) {
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setTo(to);
            message.setSubject("Faktura Proforma - DavTro Rentals - " + bookingId);
            message.setText(String.format("Witaj %s!\n\nTwoja rezerwacja zostala potwierdzona.\nNumer: %s\nKwota: %s zl\n\nFaktura proforma.\n\nPozdrawiamy,\nZespol DavTro Rentals", guestName, bookingId, total.toString()));
            mailSender.send(message);
            log.info("Proforma sent to: {}", to);
        } catch (Exception e) { log.error("Failed to send: {}", e.getMessage()); }
    }
}
EOF

cat > ${PROJECT_NAME}/java-app/src/main/resources/application.properties << 'EOF'
server.port=8081
spring.datasource.url=jdbc:postgresql://${DB_HOST:postgres-clusterip}:5432/davtro_rentals
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}
spring.jpa.hibernate.ddl-auto=validate
# ISTIO: brak konfiguracji SSL do Kafki - sidecar Envoy robi mTLS.
spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP:kafka-kraft:9092}
spring.kafka.consumer.group-id=spring-app-group
spring.kafka.consumer.auto-offset-reset=earliest
spring.mail.host=${SMTP_HOST:localhost}
spring.mail.port=${SMTP_PORT:587}
EOF

# ============================================
# SPARK JOBS
# ============================================
cat > ${PROJECT_NAME}/spark-jobs/build.sbt << 'EOF'
name := "davtro-spark-jobs"
version := "1.0.0"
scalaVersion := "2.12.18"
libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql-kafka-0-10" % "3.5.0",
  "org.postgresql" % "postgresql" % "42.7.1"
)
assembly / assemblyMergeStrategy := { case PathList("META-INF", xs @ _*) => xs match { case "MANIFEST.MF" :: Nil => MergeStrategy.discard case _ => MergeStrategy.first } case x => MergeStrategy.first }
EOF

cat > ${PROJECT_NAME}/spark-jobs/project/plugins.sbt << 'EOF'
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.1.5")
EOF

cat > ${PROJECT_NAME}/spark-jobs/project/build.properties << 'EOF'
sbt.version=1.10.7
EOF

cat > ${PROJECT_NAME}/spark-jobs/src/main/scala/com/davtro/jobs/MarketingAnalyticsJob.scala << 'EOF'
package com.davtro.jobs
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.Trigger
object MarketingAnalyticsJob {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder().appName("DavTro Marketing Analytics").master("spark://spark-master:7077").config("spark.sql.streaming.checkpointLocation", "/tmp/checkpoint").getOrCreate()
    import spark.implicits._
    // ISTIO: Kafka bez SSL - sidecar Envoy szyfruje ruch.
    val kafkaDF = spark.readStream.format("kafka").option("kafka.bootstrap.servers", "kafka-kraft:9092").option("subscribe", "marketing-actions").option("startingOffsets", "latest").load()
    val parsedDF = kafkaDF.selectExpr("CAST(value AS STRING) as json").select(from_json($"json", new org.apache.spark.sql.types.StructType().add("event", "string").add("property_id", "integer").add("guest_email", "string").add("booking_value", "double").add("timestamp", "string")).as("data")).select("data.*")
    val aggDF = parsedDF.withWatermark("timestamp", "10 minutes").groupBy(window($"timestamp", "5 minutes"), $"property_id").agg(count("*").as("booking_count"), sum("booking_value").as("total_revenue"), avg("booking_value").as("avg_booking_value"))
    val query = aggDF.writeStream.outputMode("update").format("console").trigger(Trigger.ProcessingTime("10 seconds")).start()
    val jdbcDF = parsedDF.writeStream.foreachBatch { (batchDF: org.apache.spark.sql.Dataset[org.apache.spark.sql.Row], batchId: Long) => batchDF.write.format("jdbc").option("url", "jdbc:postgresql://postgres-db:5432/davtro_rentals").option("dbtable", "marketing_events").option("user", "davtro").option("password", "changeme").mode("append").save() }.start()
    query.awaitTermination(); jdbcDF.awaitTermination()
  }
}
EOF

cat > ${PROJECT_NAME}/spark-jobs/Dockerfile << 'EOF'
FROM apache/spark:3.5.0
COPY target/scala-2.12/davtro-spark-jobs-assembly-1.0.0.jar /opt/spark/jobs/
CMD ["/opt/spark/bin/spark-submit","--class","com.davtro.jobs.MarketingAnalyticsJob","/opt/spark/jobs/davtro-spark-jobs-assembly-1.0.0.jar"]
EOF

# ============================================
# ISTIO – Gateway, VirtualService, PeerAuthentication, AuthorizationPolicy
# ============================================

cat > ${PROJECT_NAME}/manifests/base/istio-namespace-label.yaml << 'EOF'
# Istio: automatyczne wstrzykiwanie sidecarow do wszystkich podow w namespace.
# To jest fundament - bez tej etykiety Envoy nie zostanie dodany i mTLS nie zadziala.
apiVersion: v1
kind: Namespace
metadata:
  name: davtro02
  labels:
    istio-injection: enabled
    app.kubernetes.io/part-of: davtro-platform
EOF

cat > ${PROJECT_NAME}/manifests/base/istio-peer-auth.yaml << 'EOF'
# KROK 11 (Istio mTLS): STRICT mTLS w calym namespace.
# Envoy wymaga certyfikatu SPIFFE od KAZDEGO polaczenia wewnatrz namespace.
# Aplikacje NIE musza znac TLS - sidecar robi to transparentnie.
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: davtro02
spec:
  mtls:
    mode: STRICT
---
# Wyjatek: porty monitoringu/scrape (Prometheus, exportery) - PERMISSIVE,
# bo Prometheus nie ma sidecara i nie ma certu SPIFFE.
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: prometheus-scrape-permissive
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: prometheus
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: exporters-permissive
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: postgres-exporter
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: kafka-exporter-permissive
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: kafka-exporter
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: node-exporter-permissive
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: node-exporter
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: cert-expiry-exporter-permissive
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: cert-expiry-exporter
  mtls:
    mode: PERMISSIVE
---
# Kafka KRaft: kontroler (9093) mowi wlasnym protokolem - nie przez Envoy.
# Listener brokera (9092) jest pod mTLS przez sidecar.
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: kafka-controller-permissive
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: kafka-kraft
  portLevelMtls:
    9093:
      mode: DISABLE
EOF

cat > ${PROJECT_NAME}/manifests/base/istio-authz.yaml << 'EOF'
# KROK 11 (Istio): AuthorizationPolicy L7 - zastepuje NetworkPolicy L4.
# Sprawdza TOZSAMOSC SPIFFE (service account) i metode/sciezke HTTP.
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-ingress-gateway-to-frontend
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: frontend
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
      to:
        - operation:
            methods: ["GET", "HEAD"]
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-ingress-gateway-to-fastapi
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: fastapi-web-app
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
    - from:
        - source:
            principals: ["cluster.local/ns/davtro02/sa/frontend-sa"]
      to:
        - operation:
            methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-fastapi-to-postgres
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: postgres-db
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/davtro02/sa/fastapi-sa"
              - "cluster.local/ns/davtro02/sa/message-processor-sa"
              - "cluster.local/ns/davtro02/sa/spring-app-sa"
              - "cluster.local/ns/davtro02/sa/pgadmin-sa"
              - "cluster.local/ns/davtro02/sa/vault-bootstrap-sa"
              - "cluster.local/ns/davtro02/sa/postgres-exporter-sa"
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-apps-to-redis
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: redis
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/davtro02/sa/fastapi-sa"
              - "cluster.local/ns/davtro02/sa/message-processor-sa"
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-apps-to-kafka
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: kafka-kraft
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/davtro02/sa/fastapi-sa"
              - "cluster.local/ns/davtro02/sa/message-processor-sa"
              - "cluster.local/ns/davtro02/sa/spring-app-sa"
              - "cluster.local/ns/davtro02/sa/kafka-job-sa"
              - "cluster.local/ns/davtro02/sa/kafka-exporter-sa"
              - "cluster.local/ns/davtro02/sa/kafka-ui-sa"
              - "cluster.local/ns/davtro02/sa/spark-sa"
---
# Deny-all: nic innego nie ma prawa wejsc do namespace.
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all-fallback
  namespace: davtro02
spec:
  {}
EOF

cat > ${PROJECT_NAME}/manifests/base/istio-gateway.yaml << 'EOF'
# KROK 11 (Istio): Ingress Gateway zastepuje ingress-nginx.
# TLS termination z certem z cert-managera (Vault PKI) - Secret davtro-tls.
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: davtro-gateway
  namespace: davtro02
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: davtro-tls
      hosts:
        - "davtro.local"
        - "spark.davtro.local"
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "davtro.local"
        - "spark.davtro.local"
      tls:
        httpsRedirect: true
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: davtro-vs
  namespace: davtro02
spec:
  hosts:
    - "davtro.local"
  gateways:
    - davtro-gateway
  http:
    - match:
        - uri:
            prefix: /api
      route:
        - destination:
            host: fastapi-web-app-svc
            port:
              number: 80
      timeout: 30s
    - match:
        - uri:
            prefix: /grafana
      route:
        - destination:
            host: grafana
            port:
              number: 3000
    - match:
        - uri:
            prefix: /kafka-ui
      route:
        - destination:
            host: kafka-ui
            port:
              number: 80
    - match:
        - uri:
            prefix: /pgadmin
      route:
        - destination:
            host: pgadmin
            port:
              number: 80
    - route:
        - destination:
            host: frontend-svc
            port:
              number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: spark-vs
  namespace: davtro02
spec:
  hosts:
    - "spark.davtro.local"
  gateways:
    - davtro-gateway
  http:
    - route:
        - destination:
            host: spark-master-svc
            port:
              number: 8082
EOF

cat > ${PROJECT_NAME}/manifests/base/istio-destination-rules.yaml << 'EOF'
# KROK 11 (Istio): DestinationRule dla uslug z ruchem do sidecarow.
# Wymusza ISTIO_MUTUAL dla calego ruchu wewnetrznego.
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: default
  namespace: davtro02
spec:
  host: "*.davtro02.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: fastapi-dr
  namespace: davtro02
spec:
  host: fastapi-web-app-svc
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: postgres-dr
  namespace: davtro02
spec:
  host: postgres-clusterip
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: redis-dr
  namespace: davtro02
spec:
  host: redis
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: kafka-dr
  namespace: davtro02
spec:
  host: kafka-kraft
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF

# ============================================
# KUBERNETES MANIFESTS (Base) - BEZ NetworkPolicy L4
# ============================================

cat > ${PROJECT_NAME}/manifests/base/namespace.yaml << 'EOF'
# Namespace jest tworzony przez istio-namespace-label.yaml (z etykieta istio-injection).
# Ten plik zostaje dla zgodnosci z ArgoCD (kolejnosc zasobow).
EOF

cat > ${PROJECT_NAME}/manifests/base/serviceaccount.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: davtro-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: message-processor-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spring-app-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-job-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-ui-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pgadmin-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-exporter-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-exporter-sa
  namespace: davtro02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-bootstrap-sa
  namespace: davtro02
EOF

cat > ${PROJECT_NAME}/manifests/base/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastapi-config
  namespace: davtro02
data:
  DB_HOST: "postgres-clusterip"
  DB_PORT: "5432"
  DB_NAME: "davtro_rentals"
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
  # ISTIO: Kafka PLAINTEXT - sidecar Envoy szyfruje ruch do brokera.
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9092"
EOF

cat > ${PROJECT_NAME}/manifests/base/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  namespace: davtro02
  labels: { app: fastapi-web-app }
spec:
  replicas: 2
  selector:
    matchLabels: { app: fastapi-web-app }
  template:
    metadata:
      labels: { app: fastapi-web-app }
    spec:
      serviceAccountName: fastapi-sa
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      volumes:
        - { name: db-creds, secret: { secretName: fastapi-db-creds } }
        - { name: transit-helpers, configMap: { name: transit-helpers } }
        - { name: vault-tls, secret: { secretName: vault-tls, optional: true } }
      containers:
        - name: fastapi
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:latest
          ports: [{ containerPort: 8080 }]
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
          env:
            - { name: DB_USER_FILE, value: /etc/db-creds/username }
            - { name: DB_PASSWORD_FILE, value: /etc/db-creds/password }
            - { name: VAULT_TRANSIT_ADDR, value: "https://vault.davtro02.svc.cluster.local:8203" }
            - { name: VAULT_TRANSIT_CA_FILE, value: "/etc/vault-tls/ca.crt" }
            - { name: VAULT_TRANSIT_KEY, value: "davtro-app" }
            - { name: VAULT_TRANSIT_AUTH_ROLE, value: "davtro-transit" }
          volumeMounts:
            - { name: db-creds, mountPath: /etc/db-creds, readOnly: true }
            - { name: transit-helpers, mountPath: /usr/local/bin/transit, readOnly: true }
            - { name: vault-tls, mountPath: /etc/vault-tls, readOnly: true }
          readinessProbe:
            httpGet: { path: /api/health, port: 8080 }
            initialDelaySeconds: 5
          livenessProbe:
            httpGet: { path: /api/health, port: 8080 }
            initialDelaySeconds: 15
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
EOF

cat > ${PROJECT_NAME}/manifests/base/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-app-svc
  namespace: davtro02
spec:
  selector: { app: fastapi-web-app }
  ports:
    - port: 80
      targetPort: 8080
EOF

cat > ${PROJECT_NAME}/manifests/base/frontend.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: davtro02
  labels: { app: frontend }
spec:
  replicas: 2
  selector:
    matchLabels: { app: frontend }
  template:
    metadata:
      labels: { app: frontend }
    spec:
      serviceAccountName: frontend-sa
      containers:
        - name: nginx
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-frontend:latest
          imagePullPolicy: Always
          ports: [{ containerPort: 8080 }]
          readinessProbe:
            httpGet: { path: /, port: 8080 }
            initialDelaySeconds: 3
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /, port: 8080 }
            initialDelaySeconds: 10
            periodSeconds: 20
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 200m, memory: 128Mi }
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  namespace: davtro02
  labels: { app: frontend }
spec:
  type: ClusterIP
  selector: { app: frontend }
  ports:
    - name: http
      port: 80
      targetPort: 8080
EOF

cat > ${PROJECT_NAME}/manifests/base/hpa.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-web-app-hpa
  namespace: davtro02
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi-web-app
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }
EOF

cat > ${PROJECT_NAME}/manifests/base/pdb.yaml << 'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fastapi-web-app-pdb
  namespace: davtro02
spec:
  minAvailable: 1
  selector:
    matchLabels: { app: fastapi-web-app }
EOF

cat > ${PROJECT_NAME}/manifests/base/postgres.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: davtro02
spec:
  serviceName: postgres-clusterip
  replicas: 1
  selector:
    matchLabels: { app: postgres-db }
  template:
    metadata:
      labels: { app: postgres-db }
    spec:
      serviceAccountName: davtro-sa
      securityContext:
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
        fsGroupChangePolicy: OnRootMismatch
      initContainers:
        - name: fix-data-permissions
          image: postgres:16-alpine
          command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data"]
          securityContext:
            runAsUser: 0
            runAsGroup: 0
            runAsNonRoot: false
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits: { cpu: 100m, memory: 64Mi }
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports: [{ containerPort: 5432 }]
          env:
            - name: POSTGRES_DB
              value: davtro_rentals
            - name: POSTGRES_USER
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_USER } }
            - name: POSTGRES_PASSWORD
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_PASSWORD } }
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
  volumeClaimTemplates:
    - metadata: { name: pgdata }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 5Gi } }
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-clusterip
  namespace: davtro02
spec:
  clusterIP: None
  selector: { app: postgres-db }
  ports: [{ port: 5432, targetPort: 5432 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/redis.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: redis } }
  template:
    metadata: { labels: { app: redis } }
    spec:
      securityContext:
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
      containers:
        - name: redis
          image: redis:7-alpine
          ports: [{ containerPort: 6379 }]
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: davtro02
spec:
  selector: { app: redis }
  ports: [{ port: 6379, targetPort: 6379 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/vault.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-config
  namespace: davtro02
data:
  config-tls.hcl: |
    disable_mlock = true
    ui = true
    storage "raft" {
      path    = "/vault/data"
      node_id = "vault-0"
    }
    listener "tcp" {
      address         = "0.0.0.0:8203"
      cluster_address = "0.0.0.0:8201"
      tls_cert_file     = "/vault/tls/tls.crt"
      tls_key_file      = "/vault/tls/tls.key"
      tls_client_ca_file = "/vault/tls/ca.crt"
      tls_disable_client_certs = true
      tls_min_version   = "tls12"
    }
    telemetry {
      prometheus_retention = "12h"
      unauthenticated_metrics_access = true
      disable_hostname = true
    }
  start.sh: |
    set -eu
    test -s /vault/tls/tls.crt
    test -s /vault/tls/tls.key
    test -s /vault/tls/ca.crt
    echo "Vault: start TLS :8203"
    exec vault server -config=/vault/config/config-tls.hcl
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: davtro02
spec:
  serviceName: vault
  replicas: 1
  selector: { matchLabels: { app: vault } }
  template:
    metadata:
      labels: { app: vault }
    spec:
      serviceAccountName: davtro-sa
      securityContext:
        runAsUser: 100
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      initContainers:
        - name: fix-data-permissions
          image: hashicorp/vault:1.17
          command: ["sh", "-c", "chown -R 100:1000 /vault/data"]
          securityContext:
            runAsUser: 0
            runAsGroup: 0
            runAsNonRoot: false
          volumeMounts:
            - name: vault-data
              mountPath: /vault/data
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits: { cpu: 100m, memory: 64Mi }
      containers:
        - name: vault
          image: hashicorp/vault:1.17
          command: ["sh", "/vault/config/start.sh"]
          ports:
            - { containerPort: 8201, name: raft }
            - { containerPort: 8203, name: https }
          env:
            - name: VAULT_API_ADDR
              value: https://vault-0.vault.davtro02.svc.cluster.local:8203
            - name: VAULT_CLUSTER_ADDR
              value: http://vault-0.vault.davtro02.svc.cluster.local:8201
          readinessProbe:
            httpGet:
              path: "/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=204"
              port: 8203
              scheme: HTTPS
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: "/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=204"
              port: 8203
              scheme: HTTPS
            initialDelaySeconds: 30
            periodSeconds: 20
          volumeMounts:
            - name: vault-data
              mountPath: /vault/data
            - name: config
              mountPath: /vault/config
            - name: vault-tls
              mountPath: /vault/tls
              readOnly: true
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
      volumes:
        - name: config
          configMap: { name: vault-config }
        - name: vault-tls
          secret: { secretName: vault-tls }
  volumeClaimTemplates:
    - metadata: { name: vault-data }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 2Gi } }
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: davtro02
spec:
  selector: { app: vault }
  ports:
    - { name: raft, port: 8201, targetPort: 8201 }
    - { name: https, port: 8203, targetPort: 8203 }
EOF

cat > ${PROJECT_NAME}/manifests/base/vault-bootstrap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-bootstrap-sql
  namespace: davtro02
data:
  creation.sql: |
    CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' NOINHERIT;
    GRANT USAGE, CREATE ON SCHEMA public TO "{{name}}";
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "{{name}}";
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "{{name}}";
    GRANT "{{name}}" TO davtro WITH ADMIN OPTION;
  revocation.sql: |
    REASSIGN OWNED BY "{{name}}" TO davtro;
    DROP OWNED BY "{{name}}";
    DROP ROLE IF EXISTS "{{name}}";
  davtro-apps.hcl: |
    path "davtro/data/*" { capabilities = ["read"] }
    path "database/creds/davtro-app-rw" { capabilities = ["read"] }
  davtro-snapshot.hcl: |
    path "sys/storage/raft/snapshot" { capabilities = ["read", "create", "update", "sudo"] }
    path "sys/raft/snapshot" { capabilities = ["sudo", "read"] }
  davtro-transit.hcl: |
    path "transit/encrypt/davtro-app" { capabilities = ["update"] }
    path "transit/decrypt/davtro-app" { capabilities = ["update"] }
    path "transit/rewrap/davtro-app" { capabilities = ["update"] }
    path "transit/datakey/davtro-app" { capabilities = ["update"] }
    path "davtro/data/*" { capabilities = ["read"] }
    path "database/creds/davtro-app-rw" { capabilities = ["read"] }
  davtro-mtls.hcl: |
    path "pki/issue/davtro-internal" { capabilities = ["create", "update"] }
    path "davtro/data/*" { capabilities = ["read"] }
    path "database/creds/davtro-app-rw" { capabilities = ["read"] }
    path "transit/encrypt/davtro-app" { capabilities = ["update"] }
    path "transit/decrypt/davtro-app" { capabilities = ["update"] }
    path "transit/datakey/davtro-app" { capabilities = ["update"] }
  pki-issuer.hcl: |
    path "pki/sign/davtro-ingress" { capabilities = ["create", "update"] }
    path "pki/issue/davtro-ingress" { capabilities = ["create", "update"] }
    path "pki/sign/davtro-internal" { capabilities = ["create", "update"] }
    path "pki/issue/davtro-internal" { capabilities = ["create", "update"] }
  pki-internal.hcl: |
    path "pki/issue/davtro-internal" { capabilities = ["create", "update"] }
    path "pki/sign/davtro-internal" { capabilities = ["create", "update"] }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: davtro02-vault-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: davtro-sa
    namespace: davtro02
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: vault-bootstrap
  namespace: davtro02
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: vault-bootstrap
  namespace: davtro02
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: vault-bootstrap
subjects:
  - kind: ServiceAccount
    name: davtro-sa
    namespace: davtro02
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-bootstrap
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: vault-bootstrap } }
  template:
    metadata:
      labels: { app: vault-bootstrap }
    spec:
      serviceAccountName: vault-bootstrap-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 1000
        fsGroup: 1000
      initContainers:
        - name: fetch-kubectl
          image: docker.io/alpine/k8s:1.36.4
          command: ["sh", "-c", "cp /usr/bin/kubectl /share/kubectl"]
          volumeMounts:
            - { name: tools, mountPath: /share }
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits: { cpu: 100m, memory: 64Mi }
      containers:
        - name: ensure
          image: hashicorp/vault:1.17
          env:
            - name: VAULT_ADDR
              value: "https://vault.davtro02.svc.cluster.local:8203"
            - name: VAULT_CACERT
              value: "/etc/vault-tls/ca.crt"
          command: ["/bin/sh", "-c"]
          args:
            - |
              KUBECTL=/share/kubectl
              KEYS=/vault/data/bootstrap-keys
              log() { echo "[bootstrap] $*"; }
              vfield() { grep -o "$1" | grep -o '[a-z]*$'; }

              read_status() {
                STATUS_ERR=$(mktemp /tmp/vault-status.XXXXXX)
                vault status -format=json >"$STATUS_ERR" 2>&1
                STATUS_RC=$?
                STATUS=$(cat "$STATUS_ERR" 2>/dev/null || printf '{}')
                rm -f "$STATUS_ERR"
                [ "$STATUS_RC" -eq 0 ] || [ "$STATUS_RC" -eq 2 ]
              }

              ensure_one() {
                n=0
                while ! read_status; do
                  n=$((n + 1))
                  if [ "$n" -ge 20 ]; then
                    log "Vault nie odpowiada przez TLS (rc=$STATUS_RC): $STATUS"
                    return 1
                  fi
                  sleep 3
                done
                INIT=$(echo "$STATUS" | vfield '"initialized": *[a-z]*')
                SEALED=$(echo "$STATUS" | vfield '"sealed": *[a-z]*')
                [ -n "$INIT" ] || { log "nieparsowalny status"; return 1; }
                if [ "$INIT" != "true" ]; then
                  log "brak inicjalizacji -> vault operator init"
                  INIT_JSON=$(vault operator init -key-shares=1 -key-threshold=1 -format=json) || { log "init nieudany"; return 1; }
                  UKEY=$(printf '%s\n' "$INIT_JSON" | sed -n '/"unseal_keys_b64"/{n;s/[^A-Za-z0-9+\/=]//g;p;q}')
                  RTOKEN=$(echo "$INIT_JSON" | sed -n 's/.*"root_token": *"\([^"]*\)".*/\1/p')
                  [ -n "$UKEY" ] && [ -n "$RTOKEN" ] || { log "nie udalo sie wyciagnac kluczy"; return 1; }
                  printf '%s\n%s\n' "$UKEY" "$RTOKEN" > "$KEYS"
                  chmod 600 "$KEYS"
                fi
                [ -f "$KEYS" ] || { log "brak $KEYS - patrz README"; return 1; }
                SEALED=$(echo "$STATUS" | vfield '"sealed": *[a-z]*')
                if [ "$SEALED" = "true" ]; then
                  vault operator unseal "$(head -n1 "$KEYS")" >/dev/null
                fi
                export VAULT_TOKEN="$(tail -n1 "$KEYS")"
                if ! vault token lookup -format=json >/dev/null 2>&1; then
                  log "root token nieaktualny - konfiguracja wstrzymana"
                  return 1
                fi
                n=0
                until read_status && [ "$(echo "$STATUS" | vfield '"sealed": *[a-z]*')" = "false" ]; do
                  n=$((n + 1)); [ "$n" -ge 30 ] && { log "vault nadal sealed"; return 1; }
                  sleep 2
                  vault operator unseal "$(head -n1 "$KEYS")" >/dev/null 2>&1 || true
                done
                vault audit list 2>/dev/null | grep -q 'file/' || vault audit enable file file_path=stdout
                vault secrets list 2>/dev/null | grep -q 'davtro/' || vault secrets enable -path=davtro kv-v2
                ALIGN=0
                if ! vault kv get davtro/db >/dev/null 2>&1; then
                  PGPASS="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)"
                  [ -n "$PGPASS" ] || PGPASS="Davtro$(date +%s)x1"
                  vault kv put davtro/db DB_USER=davtro DB_PASSWORD="$PGPASS"
                  ALIGN=1
                fi
                vault kv get davtro/smtp >/dev/null 2>&1 || vault kv put davtro/smtp SMTP_USER='' SMTP_PASSWORD=''
                if ! vault kv get davtro/auth >/dev/null 2>&1; then
                  ADMINPASS="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)"
                  [ -n "$ADMINPASS" ] || ADMINPASS="DavtroAdmin$(date +%s)x1"
                  vault kv put davtro/auth ADMIN_PASSWORD="$ADMINPASS"
                fi
                vault auth list 2>/dev/null | grep -q 'kubernetes/' || vault auth enable kubernetes
                vault write auth/kubernetes/config \
                  kubernetes_host="https://kubernetes.default.svc" \
                  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
                  disable_iss_validation=true >/dev/null
                vault policy write davtro-apps /sql/davtro-apps.hcl >/dev/null
                vault write auth/kubernetes/role/davtro-apps \
                  bound_service_account_names=davtro-sa \
                  bound_service_account_namespaces=davtro02 \
                  policies=davtro-apps ttl=1h >/dev/null
                DB_PASSWORD=$(vault kv get -field=DB_PASSWORD davtro/db)
                vault secrets list 2>/dev/null | grep -q 'database/' || vault secrets enable database
                if ! vault write database/config/davtro-postgresql \
                    plugin_name=postgresql-database-plugin \
                    allowed_roles=davtro-app-rw \
                    connection_url="postgresql://{{username}}:{{password}}@postgres-clusterip.davtro02.svc.cluster.local:5432/davtro_rentals?sslmode=disable" \
                    username=davtro password="$DB_PASSWORD" >/dev/null 2>&1; then
                  ALIGN=1
                fi
                if [ "$ALIGN" = "1" ]; then
                  if $KUBECTL -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -tAc \
                      "ALTER USER davtro WITH PASSWORD '$DB_PASSWORD';" >/dev/null 2>&1; then
                    log "haslo davtro zsynchronizowane"
                  else
                    log "ALTER USER nieudany - retry"
                    return 1
                  fi
                  vault write database/config/davtro-postgresql \
                    plugin_name=postgresql-database-plugin \
                    allowed_roles=davtro-app-rw \
                    connection_url="postgresql://{{username}}:{{password}}@postgres-clusterip.davtro02.svc.cluster.local:5432/davtro_rentals?sslmode=disable" \
                    username=davtro password="$DB_PASSWORD" >/dev/null
                fi
                if ! $KUBECTL -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -tAc \
                    "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS user_id INT;
                     ALTER TABLE bookings ADD COLUMN IF NOT EXISTS username VARCHAR(100);" >/dev/null 2>&1; then
                  log "ALTER TABLE bookings nieudany - retry"
                  return 1
                fi
                vault write database/roles/davtro-app-rw \
                  db_name=davtro-postgresql \
                  creation_statements=@/sql/creation.sql \
                  revocation_statements=@/sql/revocation.sql \
                  default_ttl=1h max_ttl=24h >/dev/null
                vault policy write davtro-snapshot /sql/davtro-snapshot.hcl >/dev/null
                vault write auth/kubernetes/role/davtro-snapshot \
                  bound_service_account_names=davtro-sa \
                  bound_service_account_namespaces=davtro02 \
                  policies=davtro-snapshot ttl=1h >/dev/null
                if ! vault secrets list 2>/dev/null | grep -q '^pki/'; then
                  vault secrets enable -path=pki pki >/dev/null
                fi
                vault secrets tune -max-lease-ttl=87600h pki >/dev/null 2>&1 || true
                if ! vault read pki/cert/ca >/dev/null 2>&1; then
                  vault write -field=certificate pki/root/generate/internal \
                    common_name="davtro-internal CA" \
                    ttl=87600h key_type=rsa key_bits=2048 >/dev/null
                fi
                vault write pki/roles/davtro-ingress \
                  allowed_domains="davtro.local,spark.davtro.local" \
                  allow_subdomains=true allow_bare_domains=true \
                  max_ttl=2160h key_type=rsa key_bits=2048 >/dev/null
                vault write pki/roles/davtro-internal \
                  allowed_domains="svc.cluster.local,cluster.local,davtro02,davtro02.svc" \
                  allow_subdomains=true allow_bare_domains=true \
                  allow_any_name=true enforce_hostnames=false \
                  max_ttl=2160h key_type=rsa key_bits=2048 >/dev/null
                vault policy write pki-issuer /sql/pki-issuer.hcl >/dev/null
                vault write auth/kubernetes/role/cert-manager \
                  bound_service_account_names="cert-manager,cert-manager-vault" \
                  bound_service_account_namespaces="cert-manager" \
                  policies=pki-issuer ttl=1h >/dev/null
                vault policy write pki-internal /sql/pki-internal.hcl >/dev/null
                vault write auth/kubernetes/role/cert-manager-internal \
                  bound_service_account_names="cert-manager,cert-manager-vault" \
                  bound_service_account_namespaces="cert-manager" \
                  policies=pki-internal ttl=1h >/dev/null
                if ! vault secrets list 2>/dev/null | grep -q '^transit/'; then
                  vault secrets enable transit >/dev/null
                fi
                if ! vault read transit/keys/davtro-app >/dev/null 2>&1; then
                  vault write -f transit/keys/davtro-app \
                    type=aes256-gcm96 \
                    auto_rotate_period=720h >/dev/null
                fi
                vault policy write davtro-transit /sql/davtro-transit.hcl >/dev/null
                vault write auth/kubernetes/role/davtro-transit \
                  bound_service_account_names=davtro-sa \
                  bound_service_account_namespaces=davtro02 \
                  policies=davtro-transit ttl=1h >/dev/null
                vault policy write davtro-mtls /sql/davtro-mtls.hcl >/dev/null
                vault write auth/kubernetes/role/davtro-mtls \
                  bound_service_account_names=davtro-sa \
                  bound_service_account_namespaces=davtro02 \
                  policies=davtro-mtls ttl=1h >/dev/null
                log "DONE - Vault skonfigurowany (Istio mTLS + Transit)"
                return 0
              }

              while true; do
                if ensure_one; then
                  log "OK - nastepny check za 60s"
                else
                  log "BLAD - retry za 60s"
                fi
                sleep 60
              done
          volumeMounts:
            - { name: vault-data, mountPath: /vault/data }
            - { name: sql, mountPath: /sql, readOnly: true }
            - { name: tools, mountPath: /share, readOnly: true }
            - { name: vault-tls, mountPath: /etc/vault-tls, readOnly: true }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 250m, memory: 256Mi }
      volumes:
        - name: vault-data
          persistentVolumeClaim:
            claimName: vault-data-vault-0
        - name: sql
          configMap:
            name: vault-bootstrap-sql
        - name: tools
          emptyDir: {}
        - name: vault-tls
          secret: { secretName: vault-tls }
EOF

cat > ${PROJECT_NAME}/manifests/base/vault-snapshot.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vault-backup
  namespace: davtro02
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: microk8s-hostpath
  resources: { requests: { storage: 2Gi } }
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vault-snapshot
  namespace: davtro02
spec:
  schedule: "0 3 * * *"
  suspend: false
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        metadata:
          labels: { app: vault-snapshot }
        spec:
          serviceAccountName: davtro-sa
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 100
            runAsGroup: 1000
            fsGroup: 1000
          containers:
            - name: snapshot
              image: hashicorp/vault:1.17
              env:
                - name: VAULT_ADDR
                  value: https://vault.davtro02.svc.cluster.local:8203
                - name: VAULT_CACERT
                  value: /etc/vault-tls/ca.crt
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -e
                  SA_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
                  export VAULT_TOKEN="$(vault write -field=token auth/kubernetes/login jwt="$SA_TOKEN" role=davtro-snapshot)"
                  STAMP=$(date +%Y%m%d-%H%M%S)
                  vault operator raft snapshot save "/backup/snapshot-${STAMP}.snap"
                  find /backup -name 'snapshot-*.snap' -mtime +14 -delete
                  echo "OK: snapshot-${STAMP}.snap"
              volumeMounts:
                - name: backup
                  mountPath: /backup
                - name: vault-tls
                  mountPath: /etc/vault-tls
                  readOnly: true
              resources:
                requests: { cpu: 50m, memory: 64Mi }
                limits: { cpu: 200m, memory: 128Mi }
          volumes:
            - name: backup
              persistentVolumeClaim:
                claimName: vault-backup
            - name: vault-tls
              secret: { secretName: vault-tls, optional: true }
EOF

cat > ${PROJECT_NAME}/manifests/base/pki-issuer.yaml << 'EOF'
# cert-manager + Vault PKI: root CA dla Istio (istiod) i certy dla Ingress Gateway.
# To NIE jest mTLS aplikacji - to jest CA dla control-plane Istio i TLS zewnetrzny.
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: https://vault.davtro02.svc.cluster.local:8203
    path: pki/sign/davtro-ingress
    caProvider:
      type: Secret
      name: vault-tls
      key: ca.crt
    auth:
      tokenSecretRef:
        name: cert-manager-vault-token
        key: token
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer-internal
spec:
  vault:
    server: https://vault.davtro02.svc.cluster.local:8203
    path: pki/sign/davtro-internal
    caProvider:
      type: Secret
      name: vault-tls
      key: ca.crt
    auth:
      tokenSecretRef:
        name: cert-manager-vault-token
        key: token
EOF

cat > ${PROJECT_NAME}/manifests/base/certificates.yaml << 'EOF'
# Certy dla Ingress Gateway (Istio) - TLS zewnetrzny.
# mTLS aplikacji jest w 100% po stronie Istio (SPIFFE), te certy nie maja z nim nic wspolnego.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: davtro-tls
  namespace: davtro02
spec:
  secretName: davtro-tls
  duration: 2160h
  renewBefore: 360h
  commonName: davtro.local
  dnsNames:
    - davtro.local
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spark-tls
  namespace: davtro02
spec:
  secretName: spark-tls
  duration: 2160h
  renewBefore: 360h
  commonName: spark.davtro.local
  dnsNames:
    - spark.davtro.local
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
EOF

cat > ${PROJECT_NAME}/manifests/base/vault-server-tls.yaml << 'EOF'
# Bootstrap TLS dla serwera Vault - NIE z Vault PKI (błędne koło).
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-selfsigned
  namespace: davtro02
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-ca
  namespace: davtro02
spec:
  secretName: vault-ca
  isCA: true
  commonName: davtro-vault-ca
  duration: 87600h
  renewBefore: 8760h
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Never
  usages:
    - digital signature
    - cert sign
    - crl sign
  issuerRef:
    name: vault-selfsigned
    kind: Issuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-ca
  namespace: davtro02
spec:
  ca:
    secretName: vault-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-tls
  namespace: davtro02
spec:
  secretName: vault-tls
  duration: 720h
  renewBefore: 168h
  commonName: vault.davtro02.svc
  dnsNames:
    - vault
    - vault.davtro02
    - vault.davtro02.svc
    - vault.davtro02.svc.cluster.local
    - vault-0.vault.davtro02.svc.cluster.local
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Always
  issuerRef:
    name: vault-ca
    kind: Issuer
    group: cert-manager.io
EOF

cat > ${PROJECT_NAME}/manifests/base/secret-store.yaml << 'EOF'
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: davtro02
spec:
  provider:
    vault:
      server: "https://vault.davtro02.svc.cluster.local:8203"
      path: "davtro"
      version: "v2"
      caProvider:
        type: Secret
        name: vault-tls
        key: ca.crt
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "davtro-apps"
          serviceAccountRef:
            name: "davtro-sa"
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-dynamic
  namespace: davtro02
spec:
  provider:
    vault:
      server: "https://vault.davtro02.svc.cluster.local:8203"
      version: "v2"
      caProvider:
        type: Secret
        name: vault-tls
        key: ca.crt
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "davtro-apps"
          serviceAccountRef:
            name: "davtro-sa"
EOF

cat > ${PROJECT_NAME}/manifests/base/external-secrets.yaml << 'EOF'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: davtro-secrets
  namespace: davtro02
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: davtro-secrets
    creationPolicy: Owner
    template:
      type: Opaque
  data:
    - secretKey: DB_USER
      remoteRef:
        key: db
        property: DB_USER
    - secretKey: DB_PASSWORD
      remoteRef:
        key: db
        property: DB_PASSWORD
    - secretKey: SMTP_USER
      remoteRef:
        key: smtp
        property: SMTP_USER
    - secretKey: SMTP_PASSWORD
      remoteRef:
        key: smtp
        property: SMTP_PASSWORD
    - secretKey: ADMIN_PASSWORD
      remoteRef:
        key: auth
        property: ADMIN_PASSWORD
EOF

cat > ${PROJECT_NAME}/manifests/base/external-secrets-db-dynamic.yaml << 'EOF'
apiVersion: generators.external-secrets.io/v1alpha1
kind: VaultDynamicSecret
metadata:
  name: db-creds-davtro-app-rw
  namespace: davtro02
spec:
  provider:
    server: "https://vault.davtro02.svc.cluster.local:8203"
    caProvider:
      type: Secret
      name: vault-tls
      key: ca.crt
    auth:
      kubernetes:
        mountPath: "kubernetes"
        role: "davtro-apps"
        serviceAccountRef:
          name: "davtro-sa"
  path: database/creds/davtro-app-rw
  method: GET
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: fastapi-db-creds
  namespace: davtro02
spec:
  refreshInterval: 30m
  secretStoreRef:
    name: vault-dynamic
    kind: SecretStore
  target:
    name: fastapi-db-creds
    creationPolicy: Owner
  dataFrom:
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: VaultDynamicSecret
          name: db-creds-davtro-app-rw
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: message-processor-db-creds
  namespace: davtro02
spec:
  refreshInterval: 30m
  secretStoreRef:
    name: vault-dynamic
    kind: SecretStore
  target:
    name: message-processor-db-creds
    creationPolicy: Owner
  dataFrom:
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: VaultDynamicSecret
          name: db-creds-davtro-app-rw
EOF

cat > ${PROJECT_NAME}/manifests/base/transit-helpers.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: transit-helpers
  namespace: davtro02
data:
  transit_encrypt: |
    #!/bin/bash
    set -e
    export VAULT_ADDR="https://vault.davtro02.svc.cluster.local:8203"
    export VAULT_CACERT="/etc/vault-tls/ca.crt"
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login jwt="$TOKEN" role=davtro-transit 2>/dev/null)
    DATA=$(cat)
    PLAINTEXT=$(echo -n "$DATA" | base64 -w0)
    CIPHERTEXT=$(vault write -field=ciphertext transit/encrypt/davtro-app plaintext="$PLAINTEXT" 2>/dev/null)
    echo "$CIPHERTEXT"
  transit_decrypt: |
    #!/bin/bash
    set -e
    export VAULT_ADDR="https://vault.davtro02.svc.cluster.local:8203"
    export VAULT_CACERT="/etc/vault-tls/ca.crt"
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login jwt="$TOKEN" role=davtro-transit 2>/dev/null)
    CIPHERTEXT=$(cat)
    PLAINTEXT=$(vault write -field=plaintext transit/decrypt/davtro-app ciphertext="$CIPHERTEXT" 2>/dev/null)
    echo "$PLAINTEXT" | base64 -d
  transit_datakey: |
    #!/bin/bash
    set -e
    export VAULT_ADDR="https://vault.davtro02.svc.cluster.local:8203"
    export VAULT_CACERT="/etc/vault-tls/ca.crt"
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login jwt="$TOKEN" role=davtro-transit 2>/dev/null)
    KEY=$(vault write -field=wrapped_key transit/datakey/wrapped/davtro-app 2>/dev/null)
    echo "$KEY"
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-transit
  namespace: davtro02
spec:
  provider:
    vault:
      server: "https://vault.davtro02.svc.cluster.local:8203"
      version: "v2"
      caProvider:
        type: Secret
        name: vault-tls
        key: ca.crt
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "davtro-transit"
          serviceAccountRef:
            name: "davtro-sa"
EOF

# ============================================
# KAFKA (Istio edition - PLAINTEXT broker, Envoy mTLS)
# ============================================
cat > ${PROJECT_NAME}/manifests/base/kafka.yaml << 'EOF'
# Kafka KRaft (bez Zookeepera)
# ISTIO: broker nasluchuje na PLAINTEXT :9092, ruch do/z niego szyfruje sidecar Envoy.
# NIE MA juz:
#   - certyfikatu kafka-server-tls (mTLS na poziomie brokera)
#   - initContainerow keystores/truststore (openssl/keytool, PKCS12)
#   - zmiennych KAFKA_SSL_*
# Kontroler KRaft (9093) zostaje wewnetrzny - Istio go nie owija.
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-kraft
  namespace: davtro02
spec:
  serviceName: kafka-kraft
  replicas: 1
  selector: { matchLabels: { app: kafka-kraft } }
  template:
    metadata: { labels: { app: kafka-kraft } }
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: kafka
          image: apache/kafka:3.7.0
          ports:
            - { name: broker, containerPort: 9092 }
            - { name: controller, containerPort: 9093 }
          env:
            - { name: CLUSTER_ID, value: "MkU3OEVBNTcwNTJENDM2Qk" }
            - { name: KAFKA_NODE_ID, value: "0" }
            - { name: KAFKA_PROCESS_ROLES, value: "controller,broker" }
            - { name: KAFKA_LISTENERS, value: "PLAINTEXT://:9092,CONTROLLER://:9093" }
            - { name: KAFKA_ADVERTISED_LISTENERS, value: "PLAINTEXT://kafka-kraft:9092" }
            - { name: KAFKA_CONTROLLER_QUORUM_VOTERS, value: "0@kafka-kraft-0.kafka-kraft:9093" }
            - { name: KAFKA_CONTROLLER_LISTENER_NAMES, value: "CONTROLLER" }
            - { name: KAFKA_INTER_BROKER_LISTENER_NAME, value: "PLAINTEXT" }
            - { name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP, value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT" }
            - { name: KAFKA_LOG_DIRS, value: "/tmp/kraft-combined-logs" }
            - { name: KAFKA_AUTO_CREATE_TOPICS_ENABLE, value: "true" }
          resources:
            requests: { cpu: 200m, memory: 512Mi }
            limits: { cpu: 1, memory: 1Gi }
          volumeMounts:
            - { name: kafka-data, mountPath: /tmp/kraft-combined-logs }
  volumeClaimTemplates:
    - metadata: { name: kafka-data }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 5Gi } }
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-kraft
  namespace: davtro02
spec:
  clusterIP: None
  selector: { app: kafka-kraft }
  ports:
    - { name: broker, port: 9092, targetPort: 9092 }
    - { name: controller, port: 9093, targetPort: 9093 }
---
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topic-job
  namespace: davtro02
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded
spec:
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels: { app: kafka-topic-init }
    spec:
      serviceAccountName: kafka-job-sa
      restartPolicy: OnFailure
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: kafka-topic-init
          image: apache/kafka:3.7.0
          resources:
            requests: { cpu: 50m, memory: 128Mi }
            limits: { cpu: 200m, memory: 256Mi }
          command:
            - /bin/bash
            - -c
            - |
              /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic bookings-created --partitions 3 --replication-factor 1
              /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic email-invoices --partitions 3 --replication-factor 1
              /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-kraft:9092 --create --if-not-exists --topic marketing-actions --partitions 3 --replication-factor 1
EOF

cat > ${PROJECT_NAME}/manifests/base/message-processor.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: message-processor } }
  template:
    metadata: { labels: { app: message-processor } }
    spec:
      serviceAccountName: message-processor-sa
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      volumes:
        - { name: db-creds, secret: { secretName: message-processor-db-creds } }
        - { name: transit-helpers, configMap: { name: transit-helpers } }
        - { name: vault-tls, secret: { secretName: vault-tls, optional: true } }
      containers:
        - name: message-processor
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer:latest
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
          env:
            - { name: DB_USER_FILE, value: /etc/db-creds/username }
            - { name: DB_PASSWORD_FILE, value: /etc/db-creds/password }
            - { name: VAULT_TRANSIT_ADDR, value: "https://vault.davtro02.svc.cluster.local:8203" }
            - { name: VAULT_TRANSIT_CA_FILE, value: "/etc/vault-tls/ca.crt" }
            - { name: VAULT_TRANSIT_KEY, value: "davtro-app" }
            - { name: VAULT_TRANSIT_AUTH_ROLE, value: "davtro-transit" }
          volumeMounts:
            - { name: db-creds, mountPath: /etc/db-creds, readOnly: true }
            - { name: transit-helpers, mountPath: /usr/local/bin/transit, readOnly: true }
            - { name: vault-tls, mountPath: /etc/vault-tls, readOnly: true }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 300m, memory: 256Mi }
EOF

cat > ${PROJECT_NAME}/manifests/base/spring-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app-deployment
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: spring-app } }
  template:
    metadata: { labels: { app: spring-app } }
    spec:
      serviceAccountName: spring-app-sa
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      volumes:
        - { name: transit-helpers, configMap: { name: transit-helpers } }
        - { name: vault-tls, secret: { secretName: vault-tls, optional: true } }
      containers:
        - name: spring-app
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:latest
          ports: [{ containerPort: 8081 }]
          envFrom:
            - secretRef: { name: davtro-secrets }
          env:
            - { name: DB_HOST, value: "postgres-clusterip" }
            - { name: DB_NAME, value: "davtro_rentals" }
            # ISTIO: Kafka PLAINTEXT - sidecar Envoy szyfruje ruch.
            - { name: KAFKA_BOOTSTRAP, value: "kafka-kraft:9092" }
            - { name: VAULT_TRANSIT_ADDR, value: "https://vault.davtro02.svc.cluster.local:8203" }
            - { name: VAULT_TRANSIT_CA_FILE, value: "/etc/vault-tls/ca.crt" }
            - { name: VAULT_TRANSIT_KEY, value: "davtro-app" }
            - { name: VAULT_TRANSIT_AUTH_ROLE, value: "davtro-transit" }
          volumeMounts:
            - { name: transit-helpers, mountPath: /usr/local/bin/transit, readOnly: true }
            - { name: vault-tls, mountPath: /etc/vault-tls, readOnly: true }
          resources:
            requests: { cpu: 200m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: spring-app-svc
  namespace: davtro02
spec:
  selector: { app: spring-app }
  ports: [{ port: 80, targetPort: 8081 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/spark.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: spark-master } }
  template:
    metadata: { labels: { app: spark-master } }
    spec:
      serviceAccountName: spark-sa
      securityContext:
        runAsUser: 185
        runAsGroup: 0
        fsGroup: 0
      containers:
        - name: spark-master
          image: apache/spark:3.5.0
          command: ["/opt/spark/bin/spark-class", "org.apache.spark.deploy.master.Master", "--host", "0.0.0.0", "--port", "7077", "--webui-port", "8082"]
          ports: [{ containerPort: 7077 }, { containerPort: 8082 }]
          volumeMounts:
            - { name: spark-logs, mountPath: /opt/spark/logs }
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 768Mi }
      volumes:
        - { name: spark-logs, emptyDir: {} }
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master-svc
  namespace: davtro02
spec:
  selector: { app: spark-master }
  ports:
    - { name: rpc, port: 7077, targetPort: 7077 }
    - { name: ui, port: 8082, targetPort: 8082 }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: davtro02
spec:
  replicas: 2
  selector: { matchLabels: { app: spark-worker } }
  template:
    metadata: { labels: { app: spark-worker } }
    spec:
      serviceAccountName: spark-sa
      securityContext:
        runAsUser: 185
        runAsGroup: 0
        fsGroup: 0
      containers:
        - name: spark-worker
          image: apache/spark:3.5.0
          command: ["/opt/spark/bin/spark-class", "org.apache.spark.deploy.worker.Worker", "spark://spark-master-svc:7077"]
          volumeMounts:
            - { name: spark-logs, mountPath: /opt/spark/logs }
          env:
            - { name: SPARK_WORKER_CORES, value: "1" }
            - { name: SPARK_WORKER_MEMORY, value: "1g" }
          resources:
            requests: { cpu: 100m, memory: 512Mi }
            limits: { cpu: 500m, memory: 1Gi }
      volumes:
        - { name: spark-logs, emptyDir: {} }
EOF

# ============================================
# OBSERVABILITY (Istio: exportery PERMISSIVE)
# ============================================
cat > ${PROJECT_NAME}/manifests/base/prometheus.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: davtro02
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    rule_files:
      - /etc/prometheus/cert-alerts.yml
      - /etc/prometheus/vault-alerts.yml
    alerting:
      alertmanagers:
        - static_configs: [{ targets: ["alertmanager:9093"] }]
    scrape_configs:
      - job_name: fastapi
        static_configs: [{ targets: ["fastapi-web-app-svc:80"] }]
      - job_name: postgres-exporter
        static_configs: [{ targets: ["postgres-exporter:9187"] }]
      - job_name: kafka-exporter
        static_configs: [{ targets: ["kafka-exporter:9308"] }]
      - job_name: node-exporter
        static_configs: [{ targets: ["node-exporter:9100"] }]
      - job_name: cert-expiry-exporter
        static_configs: [{ targets: ["cert-expiry-exporter:9887"] }]
      - job_name: vault
        scheme: https
        metrics_path: /v1/sys/metrics
        tls_config:
          ca_file: /etc/prometheus-vault-tls/ca.crt
          server_name: vault.davtro02.svc.cluster.local
        static_configs: [{ targets: ["vault:8203"] }]
  cert-alerts.yml: |
    groups:
      - name: cert-expiry
        rules:
          - alert: DavtroCertExpiringSoon
            expr: davtro_cert_days_remaining < 14
            for: 1h
            labels: { severity: warning }
            annotations:
              summary: 'Certyfikat {{ $labels.secret }} wygasa za {{ $value }} dni'
          - alert: DavtroCertExpiringCritical
            expr: davtro_cert_days_remaining < 3
            for: 15m
            labels: { severity: critical }
            annotations:
              summary: 'Certyfikat {{ $labels.secret }} wygasa za {{ $value }} dni (krytycznie)'
          - alert: DavtroCertExpired
            expr: davtro_cert_days_remaining <= 0
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: 'Certyfikat {{ $labels.secret }} WYGASL'
      - name: target-health
        rules:
          - alert: DavtroTargetDown
            expr: up{job=~"cert-expiry-exporter|fastapi|postgres-exporter|kafka-exporter|node-exporter|vault"} == 0
            for: 5m
            labels: { severity: warning }
            annotations:
              summary: 'Scrape target {{ $labels.job }} nieosiagalny'
  vault-alerts.yml: |
    groups:
      - name: vault-health
        rules:
          - alert: DavtroVaultSealed
            expr: vault_status_sealed == 1
            for: 2m
            labels: { severity: critical }
            annotations:
              summary: 'Vault jest ZAPIEKETOWANY'
          - alert: DavtroVaultRaftNoLeader
            expr: max(vault_raft_peer_is_raft_leader) < 1
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: 'Brak ledera Raft'
          - alert: DavtroVaultMountNotMounted
            expr: vault_mount_status{status!="mounted"} == 1
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: 'Mount {{ $labels.path }} nie jest zamontowany'
          - alert: DavtroVaultTransitStale
            expr: time() - vault_transit_last_rotation_time > 86400 * 35
            for: 1h
            labels: { severity: warning }
            annotations:
              summary: 'Klucz Transit nie byl rotowany > 35 dni'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: prometheus } }
  template:
    metadata: { labels: { app: prometheus } }
    spec:
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
      containers:
        - name: prometheus
          image: prom/prometheus:v2.54.1
          args: ["--config.file=/etc/prometheus/prometheus.yml"]
          ports: [{ containerPort: 9090 }]
          volumeMounts:
            - { name: config, mountPath: /etc/prometheus }
            - { name: vault-tls, mountPath: /etc/prometheus-vault-tls, readOnly: true }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 300m, memory: 256Mi }
      volumes:
        - name: config
          configMap: { name: prometheus-config }
        - name: vault-tls
          secret: { secretName: vault-tls }
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: davtro02
spec:
  selector: { app: prometheus }
  ports: [{ port: 9090, targetPort: 9090 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/alertmanager.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: davtro02
data:
  alertmanager.yml.tpl: |
    global:
      resolve_timeout: 5m
      smtp_from: '__FROM__'
      smtp_smarthost: '__SMTPHOST__'
      smtp_auth_username: '__SMTPUSER__'
      smtp_auth_password: '__SMTPPASS__'
      smtp_require_tls: true
    route:
      receiver: email-default
      group_by: ['alertname', 'secret']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - matchers:
            - severity = "critical"
          receiver: email-critical
    receivers:
      - name: email-default
        email_configs:
          - to: '__TO__'
            send_resolved: true
      - name: email-critical
        email_configs:
          - to: '__TO__'
            send_resolved: true
  start.sh: |
    #!/bin/sh
    set -eu
    HOST="${SMTP_HOST:-127.0.0.1}"
    PORT="${SMTP_PORT:-25}"
    USER="${SMTP_USER:-x}"
    PASS="${SMTP_PASSWORD:-x}"
    FROM="${FROM_EMAIL:-admin@davtro.local}"
    TO="${ALERT_EMAIL_TO:-$FROM}"
    [ -n "${SMTP_HOST:-}" ] || echo "UWAGA: brak SMTP_HOST - alerty nie wysylaja email"
    sed -e "s|__FROM__|$FROM|g" \
        -e "s|__SMTPHOST__|$HOST:$PORT|g" \
        -e "s|__SMTPUSER__|$USER|g" \
        -e "s|__SMTPPASS__|$PASS|g" \
        -e "s|__TO__|$TO|g" \
        /etc/alertmanager/alertmanager.yml.tpl > /tmp/alertmanager.yml
    exec /bin/alertmanager --config.file=/tmp/alertmanager.yml --storage.path=/alertmanager
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: davtro02
  labels: { app: alertmanager }
spec:
  replicas: 1
  selector: { matchLabels: { app: alertmanager } }
  template:
    metadata:
      labels: { app: alertmanager }
    spec:
      containers:
        - name: alertmanager
          image: prom/alertmanager:v0.27.0
          command: ["/bin/sh", "/etc/alertmanager/start.sh"]
          ports: [{ containerPort: 9093 }]
          envFrom:
            - secretRef: { name: davtro-secrets }
            - configMapRef: { name: fastapi-config }
          env:
            - { name: ALERT_EMAIL_TO, value: "trojanowski.david@gmail.com" }
          volumeMounts:
            - { name: config, mountPath: /etc/alertmanager }
          readinessProbe:
            httpGet: { path: /-/ready, port: 9093 }
            initialDelaySeconds: 5
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits: { cpu: 200m, memory: 128Mi }
      volumes:
        - name: config
          configMap: { name: alertmanager-config }
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: davtro02
spec:
  selector: { app: alertmanager }
  ports: [{ port: 9093, targetPort: 9093 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/exporters.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: postgres-exporter } }
  template:
    metadata: { labels: { app: postgres-exporter } }
    spec:
      serviceAccountName: postgres-exporter-sa
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
      containers:
        - name: postgres-exporter
          image: prometheuscommunity/postgres-exporter:v0.15.0
          env:
            - name: DATA_SOURCE_URI
              value: "postgres://postgres-clusterip:5432/davtro_rentals?sslmode=disable"
            - name: DATA_SOURCE_USER
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_USER } }
            - name: DATA_SOURCE_PASS
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_PASSWORD } }
          ports: [{ containerPort: 9187 }]
          resources:
            requests: { cpu: 25m, memory: 32Mi }
            limits: { cpu: 100m, memory: 128Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: davtro02
spec:
  selector: { app: postgres-exporter }
  ports: [{ port: 9187, targetPort: 9187 }]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: kafka-exporter } }
  template:
    metadata: { labels: { app: kafka-exporter } }
    spec:
      serviceAccountName: kafka-exporter-sa
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
      containers:
        - name: kafka-exporter
          image: danielqsj/kafka-exporter:v1.7.0
          args: ["--kafka.server=kafka-kraft:9092"]
          ports: [{ containerPort: 9308 }]
          resources:
            requests: { cpu: 25m, memory: 32Mi }
            limits: { cpu: 100m, memory: 128Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: davtro02
spec:
  selector: { app: kafka-exporter }
  ports: [{ port: 9308, targetPort: 9308 }]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: davtro02
spec:
  selector: { matchLabels: { app: node-exporter } }
  template:
    metadata: { labels: { app: node-exporter } }
    spec:
      hostNetwork: true
      hostPID: true
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
      containers:
        - name: node-exporter
          image: prom/node-exporter:v1.8.2
          ports: [{ containerPort: 9100 }]
          resources:
            requests: { cpu: 25m, memory: 32Mi }
            limits: { cpu: 100m, memory: 128Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: davtro02
spec:
  selector: { app: node-exporter }
  ports: [{ port: 9100, targetPort: 9100 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/cert-expiry-exporter.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cert-expiry-exporter
  namespace: davtro02
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cert-expiry-reader
  namespace: davtro02
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cert-expiry-reader
  namespace: davtro02
subjects:
  - kind: ServiceAccount
    name: cert-expiry-exporter
    namespace: davtro02
roleRef:
  kind: Role
  name: cert-expiry-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cert-expiry-exporter-script
  namespace: davtro02
data:
  exporter.py: |
    #!/usr/bin/env python3
    import base64, json, os, ssl, tempfile, time, urllib.request
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from threading import Thread, Lock
    NS = os.getenv("NAMESPACE", "davtro02")
    PORT = int(os.getenv("PORT", "9887"))
    REFRESH = int(os.getenv("REFRESH_SECONDS", "60"))
    API = "https://%s:%s" % (os.environ.get("KUBERNETES_SERVICE_HOST", "kubernetes.default.svc"),
                             os.environ.get("KUBERNETES_SERVICE_PORT", "443"))
    SA = "/var/run/secrets/kubernetes.io/serviceaccount/"
    TOKEN = open(SA + "token").read().strip()
    CACERT = SA + "ca.crt"
    def k8s_get(path):
        ctx = ssl.create_default_context(cafile=CACERT)
        req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + TOKEN})
        with urllib.request.urlopen(req, context=ctx, timeout=10) as r:
            return json.loads(r.read())
    def not_after_epoch(pem):
        with tempfile.NamedTemporaryFile(suffix=".pem", delete=False) as f:
            f.write(pem)
            path = f.name
        try:
            info = ssl._ssl._test_decode_cert(path)
            return int(time.mktime(time.strptime(info["notAfter"], "%b %d %H:%M:%S %Y GMT")))
        finally:
            os.unlink(path)
    _cache = {"body": "# eksporter sie rozgrzewa...\n"}
    _lock = Lock()
    def refresh_loop():
        while True:
            lines = ["# HELP davtro_cert_not_after_seconds Czas wygasniecia certyfikatu (unix).",
                     "# TYPE davtro_cert_not_after_seconds gauge",
                     "# HELP davtro_cert_days_remaining Dni do wygasniecia certyfikatu.",
                     "# TYPE davtro_cert_days_remaining gauge"]
            try:
                data = k8s_get("/api/v1/namespaces/%s/secrets" % NS)
                for item in data.get("items", []):
                    if item.get("type") != "kubernetes.io/tls":
                        continue
                    name = item["metadata"]["name"]
                    crt = item.get("data", {}).get("tls.crt")
                    if not crt:
                        continue
                    try:
                        ts = not_after_epoch(base64.b64decode(crt))
                        days = int((ts - time.time()) // 86400)
                        lines.append('davtro_cert_not_after_seconds{secret="%s"} %d' % (name, ts))
                        lines.append('davtro_cert_days_remaining{secret="%s"} %d' % (name, days))
                    except Exception as exc:
                        print("cert decode error:", name, exc)
            except Exception as exc:
                print("k8s api error:", exc)
            with _lock:
                _cache["body"] = "\n".join(lines) + "\n"
            time.sleep(REFRESH)
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ("/metrics", "/healthz"):
                self.send_response(404); self.end_headers(); return
            body = b"ok\n" if self.path == "/healthz" else _cache["body"].encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *a):
            pass
    Thread(target=refresh_loop, daemon=True).start()
    print("cert-expiry-exporter nasluchuje na :%d (ns=%s, refresh=%ds)" % (PORT, NS, REFRESH))
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-expiry-exporter
  namespace: davtro02
  labels: { app: cert-expiry-exporter }
spec:
  replicas: 1
  selector: { matchLabels: { app: cert-expiry-exporter } }
  template:
    metadata:
      labels: { app: cert-expiry-exporter }
    spec:
      serviceAccountName: cert-expiry-exporter
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
      containers:
        - name: exporter
          image: python:3.12-slim
          command: ["python3", "/app/exporter.py"]
          ports: [{ containerPort: 9887 }]
          env:
            - { name: NAMESPACE, value: davtro02 }
            - { name: PORT, value: "9887" }
            - { name: REFRESH_SECONDS, value: "60" }
          volumeMounts:
            - { name: script, mountPath: /app }
          readinessProbe:
            httpGet: { path: /healthz, port: 9887 }
            initialDelaySeconds: 3
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits: { cpu: 100m, memory: 64Mi }
      volumes:
        - name: script
          configMap: { name: cert-expiry-exporter-script }
---
apiVersion: v1
kind: Service
metadata:
  name: cert-expiry-exporter
  namespace: davtro02
spec:
  selector: { app: cert-expiry-exporter }
  ports: [{ port: 9887, targetPort: 9887 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/grafana.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  namespace: davtro02
data:
  datasource.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus:9090
        access: proxy
        isDefault: true
      - name: Loki
        type: loki
        url: http://loki:3100
        access: proxy
      - name: Tempo
        type: tempo
        url: http://tempo:3200
        access: proxy
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: davtro02
data:
  davtro-overview.json: |
    { "title": "Davtro Platform Overview", "panels": [] }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: grafana } }
  template:
    metadata: { labels: { app: grafana } }
    spec:
      securityContext:
        runAsUser: 472
        runAsGroup: 472
        fsGroup: 472
      containers:
        - name: grafana
          image: grafana/grafana:11.2.0
          ports: [{ containerPort: 3000 }]
          volumeMounts:
            - { name: datasource, mountPath: /etc/grafana/provisioning/datasources }
            - { name: dashboards, mountPath: /etc/grafana/provisioning/dashboards-data }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 512Mi }
      volumes:
        - name: datasource
          configMap: { name: grafana-datasource }
        - name: dashboards
          configMap: { name: grafana-dashboards }
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: davtro02
spec:
  selector: { app: grafana }
  ports: [{ port: 3000, targetPort: 3000 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/loki.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: davtro02
data:
  loki-config.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h
    storage_config:
      tsdb_shipper:
        active_index_directory: /loki/index
        cache_location: /loki/cache
      filesystem:
        directory: /loki/chunks
    compactor:
      working_directory: /loki/compactor
    limits_config:
      allow_structured_metadata: false
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: loki } }
  template:
    metadata: { labels: { app: loki } }
    spec:
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
        - name: loki
          image: grafana/loki:3.1.1
          args: ["-config.file=/etc/loki/loki-config.yaml"]
          ports: [{ containerPort: 3100 }]
          volumeMounts:
            - { name: data, mountPath: /loki }
            - { name: config, mountPath: /etc/loki }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 512Mi }
      volumes:
        - name: data
          emptyDir: {}
        - name: config
          configMap: { name: loki-config }
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: davtro02
spec:
  selector: { app: loki }
  ports: [{ port: 3100, targetPort: 3100 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/promtail.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: davtro02
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
    positions:
      filename: /tmp/positions.yaml
    clients:
      - url: http://loki:3100/loki/api/v1/push
    scrape_configs:
      - job_name: containers
        static_configs:
          - targets:
              - localhost
            labels:
              job: containerlogs
              __path__: /var/log/containers/*.log
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: davtro02
spec:
  selector: { matchLabels: { app: promtail } }
  template:
    metadata: { labels: { app: promtail } }
    spec:
      serviceAccountName: davtro-sa
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
        - name: promtail
          image: grafana/promtail:3.1.1
          args: ["-config.file=/etc/promtail/promtail.yaml"]
          volumeMounts:
            - { name: config, mountPath: /etc/promtail }
            - { name: varlog, mountPath: /var/log }
            - { name: pods, mountPath: /var/log/pods, readOnly: true }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 200m, memory: 256Mi }
      volumes:
        - name: config
          configMap: { name: promtail-config }
        - name: varlog
          hostPath: { path: /var/log }
        - name: pods
          hostPath: { path: /var/log/pods }
EOF

cat > ${PROJECT_NAME}/manifests/base/tempo.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: davtro02
data:
  tempo.yaml: |
    server: { http_listen_port: 3200 }
    distributor:
      receivers:
        otlp:
          protocols: { http: {}, grpc: {} }
    storage:
      trace: { backend: local, local: { path: /tmp/tempo/traces } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: tempo } }
  template:
    metadata: { labels: { app: tempo } }
    spec:
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
        - name: tempo
          image: grafana/tempo:2.6.0
          args: ["-config.file=/etc/tempo/tempo.yaml"]
          ports: [{ containerPort: 3200 }]
          volumeMounts:
            - { name: config, mountPath: /etc/tempo }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 250m, memory: 256Mi }
      volumes:
        - name: config
          configMap: { name: tempo-config }
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: davtro02
spec:
  selector: { app: tempo }
  ports: [{ port: 3200, targetPort: 3200 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/pgadmin.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: pgadmin } }
  template:
    metadata: { labels: { app: pgadmin } }
    spec:
      serviceAccountName: pgadmin-sa
      securityContext:
        runAsUser: 5050
        runAsGroup: 5050
        fsGroup: 5050
      containers:
        - name: pgadmin
          image: dpage/pgadmin4:8
          env:
            - { name: PGADMIN_DEFAULT_EMAIL, value: admin@davtro.pl }
            - name: PGADMIN_DEFAULT_PASSWORD
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: DB_PASSWORD } }
          ports: [{ containerPort: 80 }]
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 512Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: davtro02
spec:
  selector: { app: pgadmin }
  ports: [{ port: 80, targetPort: 80 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/kafka-ui.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: davtro02
spec:
  replicas: 1
  selector: { matchLabels: { app: kafka-ui } }
  template:
    metadata: { labels: { app: kafka-ui } }
    spec:
      serviceAccountName: kafka-ui-sa
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
        - name: kafka-ui
          image: provectuslabs/kafka-ui:latest
          env:
            - { name: KAFKA_CLUSTERS_0_NAME, value: davtro }
            - { name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS, value: "kafka-kraft:9092" }
          ports: [{ containerPort: 8080 }]
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: davtro02
spec:
  selector: { app: kafka-ui }
  ports: [{ port: 80, targetPort: 8080 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/kyverno-policy.yaml << 'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: davtro-baseline-policy
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-resource-requests-limits
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro02]
      validate:
        message: "Kazdy kontener musi miec zdefiniowane requests/limits."
        pattern:
          spec:
            containers:
              - resources:
                  requests:
                    cpu: "?*"
                    memory: "?*"
                  limits:
                    cpu: "?*"
                    memory: "?*"
    - name: disallow-privileged
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro02]
      validate:
        message: "Kontenery uprzywilejowane sa niedozwolone."
        pattern:
          spec:
            =(securityContext):
              =(privileged): "false"
EOF

# ============================================
# KUSTOMIZATION
# ============================================
cat > ${PROJECT_NAME}/manifests/base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
# Namespace + Istio injection
- istio-namespace-label.yaml
# ServiceAccounts
- serviceaccount.yaml
# Istio resources
- istio-peer-auth.yaml
- istio-authz.yaml
- istio-gateway.yaml
- istio-destination-rules.yaml
# Secrets / Vault
- configmap.yaml
- secret-store.yaml
- external-secrets.yaml
- external-secrets-db-dynamic.yaml
- transit-helpers.yaml
- vault.yaml
- vault-snapshot.yaml
- vault-bootstrap.yaml
- vault-server-tls.yaml
- pki-issuer.yaml
- certificates.yaml
# Applications
- deployment.yaml
- service.yaml
- frontend.yaml
- message-processor.yaml
- spring-app.yaml
- spark.yaml
# Data
- postgres.yaml
- redis.yaml
- kafka.yaml
# Autoscaling / availability
- hpa.yaml
- pdb.yaml
# Observability
- prometheus.yaml
- alertmanager.yaml
- exporters.yaml
- cert-expiry-exporter.yaml
- grafana.yaml
- loki.yaml
- promtail.yaml
- tempo.yaml
# Tools
- pgadmin.yaml
- kafka-ui.yaml
# Policy
- kyverno-policy.yaml

images:
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
  newTag: latest
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
  newTag: latest
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-frontend
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-frontend
  newTag: latest
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spark
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spark
  newTag: latest
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
  newTag: latest
EOF

cat > ${PROJECT_NAME}/manifests/overlays/production/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: davtro02
resources:
  - ../../base
replicas:
  - name: fastapi-web-app
    count: 3
EOF

cat > ${PROJECT_NAME}/manifests/overlays/staging/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: davtro02-staging
resources:
  - ../../base
replicas:
  - name: fastapi-web-app
    count: 1
EOF

# ============================================
# ARGOCD
# ============================================
cat > ${PROJECT_NAME}/argocd/application.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtro-website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01.git
    targetRevision: HEAD
    path: manifests/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: davtro02
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# ============================================
# TERRAFORM
# ============================================
cat > ${PROJECT_NAME}/terraform/main.tf << 'EOF'
terraform {
  cloud {
    organization = "davtro02"
    workspaces { name = "github-actions-terraform" }
  }
  required_providers {
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}
provider "github" { token = var.github_token }
variable "github_token" { type = string, sensitive = true }
variable "ghcr_pat" { type = string, sensitive = true }
resource "github_repository" "repo" {
  name        = "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
  description = "Davtro Apartments - platforma wynajmu z Istio mTLS"
  visibility  = "private"
}
resource "github_actions_secret" "ghcr_pat" {
  repository      = github_repository.repo.name
  secret_name     = "GHCR_PAT"
  plaintext_value = var.ghcr_pat
}
EOF

# ============================================
# GITHUB ACTIONS CI/CD
# ============================================
cat > ${PROJECT_NAME}/.github/workflows/ci-cd.yaml << 'EOF'
name: CI/CD - Davtro Platform (Istio)
permissions:
  contents: write
  packages: write
on:
  push:
    branches: [main]
  workflow_dispatch:
env:
  REGISTRY: ghcr.io
  IMAGE_BASE: ghcr.io/${{ github.repository_owner }}/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
jobs:
  build-fastapi:
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with: { registry: "${{ env.REGISTRY }}", username: "${{ github.actor }}", password: "${{ secrets.GHCR_PAT_02 }}" }
      - uses: docker/build-push-action@v6
        with:
          context: ./backend-fastapi
          file: ./backend-fastapi/Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}:latest
            ${{ env.IMAGE_BASE }}:${{ github.sha }}
  build-frontend:
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with: { registry: "${{ env.REGISTRY }}", username: "${{ github.actor }}", password: "${{ secrets.GHCR_PAT_02 }}" }
      - uses: docker/build-push-action@v6
        with:
          context: ./frontend
          file: ./frontend/Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-frontend:latest
            ${{ env.IMAGE_BASE }}-frontend:${{ github.sha }}
  build-consumer:
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with: { registry: "${{ env.REGISTRY }}", username: "${{ github.actor }}", password: "${{ secrets.GHCR_PAT_02 }}" }
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: Dockerfile.consumer
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-consumer:latest
            ${{ env.IMAGE_BASE }}-consumer:${{ github.sha }}
  build-spring:
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v5
        with: { distribution: temurin, java-version: '17' }
      - uses: docker/login-action@v3
        with: { registry: "${{ env.REGISTRY }}", username: "${{ github.actor }}", password: "${{ secrets.GHCR_PAT_02 }}" }
      - run: mvn -f java-app/pom.xml clean package -DskipTests
      - uses: docker/build-push-action@v6
        with:
          context: ./java-app
          file: ./java-app/Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-spring:latest
            ${{ env.IMAGE_BASE }}-spring:${{ github.sha }}
  build-spark:
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v5
        with: { distribution: temurin, java-version: '17' }
      - uses: sbt/setup-sbt@v1
      - uses: docker/login-action@v3
        with: { registry: "${{ env.REGISTRY }}", username: "${{ github.actor }}", password: "${{ secrets.GHCR_PAT_02 }}" }
      - run: cd spark-jobs && sbt -batch clean assembly
      - uses: docker/build-push-action@v6
        with:
          context: ./spark-jobs
          file: ./spark-jobs/Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-spark:latest
            ${{ env.IMAGE_BASE }}-spark:${{ github.sha }}
  update-manifests:
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    needs: [build-fastapi, build-frontend, build-consumer, build-spring, build-spark]
    steps:
      - uses: actions/checkout@v4
        with: { token: "${{ secrets.GHCR_PAT_02 }}" }
      - run: |
          curl --fail --silent --show-error \
            -H "Authorization: Bearer ${{ github.token }}" \
            "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          cd manifests/base
          ../../kustomize edit set image \
            ${{ env.IMAGE_BASE }}=${{ env.IMAGE_BASE }}:${{ github.sha }} \
            ${{ env.IMAGE_BASE }}-frontend=${{ env.IMAGE_BASE }}-frontend:${{ github.sha }} \
            ${{ env.IMAGE_BASE }}-consumer=${{ env.IMAGE_BASE }}-consumer:${{ github.sha }} \
            ${{ env.IMAGE_BASE }}-spring=${{ env.IMAGE_BASE }}-spring:${{ github.sha }} \
            ${{ env.IMAGE_BASE }}-spark=${{ env.IMAGE_BASE }}-spark:${{ github.sha }}
      - run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add manifests/base/kustomization.yaml
          git diff --cached --quiet || git commit -m "ci: aktualizacja obrazow na ${{ github.sha }}"
          git push
EOF

# ============================================
# DOCS
# ============================================
cat > ${PROJECT_NAME}/README.md << 'EOF'
# Davtro Apartments – Istio Edition

Platforma wynajmu krótkoterminowego z **Istio mTLS** zamiast ręcznego zarządzania certyfikatami aplikacji.

## Co się zmieniło względem wersji klasycznej

### A. Usunięto z manifestów K8s
- **Wszystkie `Certificate` mTLS aplikacji** (`fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls`) – zastąpione przez Envoy SPIFFE.
- **`kafka-server-tls`** i konfiguracja `KAFKA_SSL_*` – broker nasłuchuje na PLAINTEXT `9092`, sidecar szyfruje.
- **InitContainers `keystores` i `truststore`** (openssl/keytool/PKCS12) – Istio zarządza certami w RAM sidecarów, rotacja co 24h bez restartu.
- **NetworkPolicy L4** (`default-deny-ingress`, `allow-intra-namespace`, itd.) – zastąpione przez:
  - `PeerAuthentication STRICT` (wymusza mTLS w całym namespace),
  - `AuthorizationPolicy` (L7: tożsamość SPIFFE, metody HTTP, ścieżki).
- **Ingress NGINX + `Ingress` + `Certificates davtro-tls/spark-tls` dla kontrolera** – zastąpione przez Istio Gateway + VirtualService (certy nadal z cert-managera/Vault PKI, ale dla **Ingress Gateway**, nie dla aplikacji).

### B. Usunięto z kodu aplikacji
- **FastAPI/Spring**: parametry `KAFKA_SSL_*`, `security.protocol=SSL`, `ssl.keystore.*`, `ssl.truststore.*`.
- **confluent-kafka**: `security.protocol`, `ssl.*` – zwykły PLAINTEXT do `kafka-kraft:9092`.
- **Java `application.properties`**: `spring.kafka.properties.ssl.*`.

### C. Zostaje (Istio tego nie zastępuje)
- **HashiCorp Vault** – Transit (PII w spoczynku), dynamiczne credsy DB, KV, PKI (Root CA dla Istio i Ingress Gateway).
- **External Secrets Operator** – most Vault → K8s Secrets.
- **cert-manager** – wystawia certy dla **Istio Ingress Gateway** i Vaulta (bootstrap TLS), nie dla aplikacji.
- **Kyverno** – walidacja manifestów podów.
- **Vault PKI** – Root CA dla istiod (`cacerts`) i certy zewnętrznych.

## Wymagania wstępne

```bash
# 1. Istio (z mTLS STRICT, profile: default z ingress gateway)
istioctl install --set profile=default -y

# 2. cert-manager (dla certów Ingress Gateway i Vaulta)
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true

# 3. External Secrets Operator
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# 4. Kyverno
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# 5. Konfiguracja Istio z Vault PKI jako Root CA (opcjonalnie, dla zgodności)
#    W praktyce: istiod ma własne self-signed CA; Vault PKI jest dla Ingress Gateway.