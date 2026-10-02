#!/bin/bash
set -e

PROJECT_NAME="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02"
NAMESPACE="davtro"
REPO="https://github.com/exea-centrum/${PROJECT_NAME}.git"

echo "=== DavTro Rentals - All-in-One Setup (Combined & Fixed) ==="
mkdir -p ${PROJECT_NAME}/{frontend,backend-fastapi/app/{templates,static},java-app/src/main/{java/com/davtro/rental/{model,repository,consumer,service},resources},spark-jobs/src/main/scala/com/davtro/jobs,spark-jobs/project,manifests/{base,overlays/{production,staging},argocd},terraform,.github/workflows,docs,kyverno-policies,argocd}

# ============================================
# GIT
# ============================================

cat > ${PROJECT_NAME}/.gitignore << 'EOF'
__pycache__/
EOF

# ============================================
# FRONTEND
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
      <p class="text-xl text-gray-400 max-w-2xl mx-auto mb-10">Nowoczesna platforma z Kafka, Redis, PostgreSQL, Vault, Spark i Spring Boot</p>
      <div class="flex justify-center gap-4">
        <button onclick="showSection('properties')" class="px-8 py-4 bg-blue-600 rounded-xl font-semibold hover:scale-105 transition">Przeglądaj Oferty</button>
        <button onclick="showSection('calendar')" class="px-8 py-4 glass rounded-xl font-semibold hover:scale-105 transition">Sprawdź Dostępność</button>
      </div>
    </div>
    <div class="grid md:grid-cols-4 gap-6 mb-12">
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-database text-3xl text-blue-400 mb-3"></i><h3 class="font-bold">PostgreSQL</h3><p class="text-sm text-gray-400">Trwały zapis danych</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-bolt text-3xl text-yellow-400 mb-3"></i><h3 class="font-bold">Apache Kafka</h3><p class="text-sm text-gray-400">Stream processing</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-server text-3xl text-red-400 mb-3"></i><h3 class="font-bold">Redis Cache</h3><p class="text-sm text-gray-400">Szybki cache</p></div>
      <div class="glass rounded-2xl p-6 text-center"><i class="fas fa-shield-alt text-3xl text-purple-400 mb-3"></i><h3 class="font-bold">HashiCorp Vault</h3><p class="text-sm text-gray-400">Bezpieczne sekrety</p></div>
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
          <p class="text-xs text-gray-500 text-center"><i class="fas fa-lock mr-1"></i>Rezerwacja: Redis → Kafka → PostgreSQL. Faktura proforma na email.</p>
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
        <p class="text-xs text-gray-500 text-center"><i class="fas fa-shield-alt mr-1"></i>Hasła: PBKDF2-SHA256; sesja: token w Redis (TTL 24h). Twoje dane widzisz tylko Ty i administrator.</p>
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
// Metadane WYLACZNIE prezentacyjne (emoji/ocena). Nazwy, ceny, opisy i dostepnosc
// pochodza z API -> PostgreSQL (GET /api/properties), nie z tego pliku.
const PROPERTY_META=[
  {id:1,name:"Apartament Premium - Warszawa",location:"warsaw",price:450,guests:4,image:"🏙️",rating:4.9,amenities:["WiFi","Klimatyzacja","Balkon","Parking"],description:"Luksusowy apartament w centrum Warszawy."},
  {id:2,name:"Studio Modern - Kraków",location:"krakow",price:320,guests:2,image:"🏰",rating:4.8,amenities:["WiFi","Smart TV","Kuchnia"],description:"Stylowe studio obok Rynku Głównego."},
  {id:3,name:"Villa nad Morzem - Gdańsk",location:"gdansk",price:680,guests:6,image:"🌊",rating:4.9,amenities:["WiFi","Ogródek","Grill","Parking"],description:"Willa 200m od plaży."},
  {id:4,name:"Loft Industrial - Wrocław",location:"wroclaw",price:280,guests:3,image:"🏭",rating:4.7,amenities:["WiFi","Projektor","Klimatyzacja"],description:"Industrialny loft w Nadodrzu."},
  {id:5,name:"Penthouse View - Warszawa",location:"warsaw",price:850,guests:4,image:"🌆",rating:5.0,amenities:["WiFi","Basen","Siłownia","Concierge"],description:"Ekskluzywny penthouse z tarasem."},
  {id:6,name:"Apartament Royal - Kraków",location:"krakow",price:390,guests:4,image:"👑",rating:4.8,amenities:["WiFi","Klimatyzacja","Balkon"],description:"Elegancki apartament w Kazimierzu."}
];
// --- Stan aplikacji (zrodlem prawdy jest API: PostgreSQL + liczniki Kafki) ---
let properties=[];            // z GET /api/properties (PostgreSQL)
let bookings=[];              // z GET /api/bookings   (PostgreSQL)
// KROK 5 (Auth): zalogowany rezerwujacy + token sesyjny (localStorage).
let currentUser=null;
let authToken=localStorage.getItem('davtro_token')||null;
function authHeaders(){return authToken?{'Authorization':'Bearer '+authToken}:{}}
let kafkaTopics={};           // z /kafka-metrics       (offsety topicow Kafki)
let currentMonth=new Date();
let selectedDates=[];
async function apiJson(path,options){options=Object.assign({},options||{});options.headers=Object.assign({},options.headers||{},authHeaders());const res=await fetch(path,options);if(!res.ok){const body=(await res.text()).slice(0,180);throw new Error('HTTP '+res.status+' '+body);}return res.json();}
function mapProperty(p){const meta=PROPERTY_META.find(m=>String(m.id)===String(p.id))||{};return{id:p.id,name:p.name,location:p.location,price:Number(p.price),guests:p.guests,description:p.description||'',amenities:Array.isArray(p.amenities)?p.amenities:[],image:meta.image||'🏠',rating:meta.rating||4.8};}
function mapBooking(b){const ci=b.check_in,co=b.check_out;return{id:b.id,propertyId:b.property_id,propertyName:b.property_name,guestName:b.guest_name,email:b.email,phone:b.phone||'',checkIn:ci,checkOut:co,nights:Math.max(0,Math.round((new Date(co)-new Date(ci))/86400000)),totalPrice:b.total_price==null?null:Number(b.total_price),status:b.status,createdAt:b.created_at,masked:!!b.masked,mine:!!b.mine};}
async function loadProperties(){try{properties=(await apiJson('/api/properties')).map(mapProperty);}catch(e){console.error('GET /api/properties:',e);showToast('Błąd','Brak danych z API (/api/properties): '+e.message,'error');}}
async function loadBookings(){try{bookings=(await apiJson('/api/bookings')).map(mapBooking);}catch(e){bookings=[];console.error('GET /api/bookings:',e);showToast('Błąd','Brak danych z API (/api/bookings): '+e.message,'error');}}
async function loadKafkaMetrics(){try{const text=await (await fetch('/kafka-metrics')).text();const counts={};text.split('\n').forEach(line=>{const m=line.match(/^kafka_topic_partition_current_offset\{[^}]*topic="([^"]+)"[^}]*\}\s+(\d+)/);if(m)counts[m[1]]=(counts[m[1]]||0)+Number(m[2]);});kafkaTopics=counts;}catch(e){kafkaTopics={};console.error('GET /kafka-metrics:',e);}}
async function showSection(section){document.querySelectorAll('.section-content').forEach(s=>s.classList.add('hidden'));document.getElementById(section+'-section').classList.remove('hidden');if(section==='properties')renderProperties();if(section==='calendar'){renderCalendar();populatePropertySelect();}if(section==='login')renderLoginSection();if(section==='admin'){document.getElementById('bookings-table').innerHTML='<tr><td colspan="6" class="py-8 text-center text-gray-500">Ładowanie z PostgreSQL…</td></tr>';await loadBookings();await loadKafkaMetrics();renderAdmin();}}
function showToast(title,message,type='success'){const toast=document.getElementById('toast');document.getElementById('toast-title').textContent=title;document.getElementById('toast-message').textContent=message;toast.classList.remove('translate-y-20','opacity-0');setTimeout(()=>toast.classList.add('translate-y-20','opacity-0'),4000);}
function createPropertyCard(prop){return`<div class="property-card glass rounded-2xl overflow-hidden"><div class="h-48 bg-gradient-to-br from-slate-700 to-slate-800 flex items-center justify-center text-6xl relative">${prop.image}<div class="absolute top-4 right-4 bg-black/50 rounded-lg px-3 py-1 text-sm font-bold"><i class="fas fa-star text-yellow-400 mr-1"></i>${prop.rating}</div></div><div class="p-6"><div class="flex items-center gap-2 text-sm text-gray-400 mb-2"><i class="fas fa-map-marker-alt text-blue-400"></i>${prop.location}</div><h3 class="text-lg font-bold mb-2">${prop.name}</h3><p class="text-sm text-gray-400 mb-4">${prop.description}</p><div class="flex flex-wrap gap-2 mb-4">${prop.amenities.map(a=>`<span class="text-xs bg-white/10 px-2 py-1 rounded">${a}</span>`).join('')}</div><div class="flex items-center justify-between"><div><span class="text-2xl font-bold text-blue-400">${prop.price} zł</span><span class="text-sm text-gray-400">/doba</span></div><button onclick="selectPropertyForBooking(${prop.id})" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition">Rezerwuj</button></div></div></div>`;}
function renderProperties(){document.getElementById('all-properties').innerHTML=properties.map(p=>createPropertyCard(p)).join('');}
function renderFeatured(){document.getElementById('featured-properties').innerHTML=properties.slice(0,3).map(p=>createPropertyCard(p)).join('');}
function renderCalendar(){const grid=document.getElementById('calendar-grid');const monthLabel=document.getElementById('calendar-month');const year=currentMonth.getFullYear(),month=currentMonth.getMonth();const monthNames=['Styczeń','Luty','Marzec','Kwiecień','Maj','Czerwiec','Lipiec','Sierpień','Wrzesień','Październik','Listopad','Grudzień'];monthLabel.textContent=`${monthNames[month]} ${year}`;grid.innerHTML='';const firstDay=new Date(year,month,1).getDay();const daysInMonth=new Date(year,month+1,0).getDate();const startOffset=firstDay===0?6:firstDay-1;for(let i=0;i<startOffset;i++)grid.innerHTML+=`<div></div>`;for(let day=1;day<=daysInMonth;day++){const dateStr=`${year}-${String(month+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;const calProp=document.getElementById('booking-property')?.value;const isBooked=bookings.some(b=>dateStr>=b.checkIn&&dateStr<=b.checkOut&&(!calProp||String(b.propertyId)===String(calProp)));const isSelected=selectedDates.includes(dateStr);const isPast=new Date(dateStr)<new Date().setHours(0,0,0,0);let classes='h-12 rounded-lg flex items-center justify-center cursor-pointer text-sm font-medium ';if(isPast)classes+='text-gray-600 cursor-not-allowed';else if(isBooked)classes+='bg-red-500/20 border border-red-500 text-red-300 cursor-not-allowed';else if(isSelected)classes+='bg-blue-500 border border-blue-400 text-white';else classes+='bg-white/5 hover:bg-white/15';const onclick=isPast||isBooked?'':`onclick="toggleDate('${dateStr}')"`;
grid.innerHTML+=`<div class="${classes}" ${onclick}>${day}</div>`;}}
function changeMonth(delta){currentMonth.setMonth(currentMonth.getMonth()+delta);renderCalendar();}
function toggleDate(dateStr){const idx=selectedDates.indexOf(dateStr);if(idx>-1)selectedDates.splice(idx,1);else if(selectedDates.length<2)selectedDates.push(dateStr);else{selectedDates=[selectedDates[1],dateStr];}selectedDates.sort();renderCalendar();if(selectedDates.length===2){document.getElementById('check-in').value=selectedDates[0];document.getElementById('check-out').value=selectedDates[1];calculatePrice();}}
function populatePropertySelect(){document.getElementById('booking-property').innerHTML='<option value="">-- Wybierz --</option>'+properties.map(p=>`<option value="${p.id}">${p.name} - ${p.price} zł/doba</option>`).join('');}
// KROK 5: jeden combobox (Nieruchomosc z formularza) steruje tez kalendarzem -
// zmiana w comboboxie przelacza widok kalendarza na dana nieruchomosc.
document.getElementById('booking-property')?.addEventListener('change',renderCalendar);
function selectPropertyForBooking(id){showSection('calendar');document.getElementById('booking-property').value=id;renderCalendar();calculatePrice();}
function calculatePrice(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;if(!propId||!checkIn||!checkOut)return;const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));if(nights>0){document.getElementById('price-per-night').textContent=prop.price+' zł';document.getElementById('night-count').textContent=nights;document.getElementById('total-price').textContent=(prop.price*nights)+' zł';}}
['booking-property','check-in','check-out'].forEach(id=>{document.getElementById(id)?.addEventListener('change',calculatePrice);});
async function submitBooking(){if(!currentUser){showToast('Wymagane logowanie','Zaloguj się, aby dokonać rezerwacji','error');showSection('login');return;}const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;const name=document.getElementById('guest-name').value;const email=document.getElementById('guest-email').value;const phone=document.getElementById('guest-phone').value;if(!propId||!checkIn||!checkOut||!name||!email){showToast('Błąd','Wypełnij wszystkie pola','error');return;}const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));const total=prop.price*nights;showToast('Przetwarzanie','FastAPI → PostgreSQL + Redis + Kafka...','info');try{const saved=await apiJson('/api/bookings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({property_id:Number(propId),guest_name:name,email:email,phone:phone,guests:prop.guests||1,check_in:checkIn,check_out:checkOut,total_price:Number(total)})});showToast('Sukces!',`Rezerwacja ${saved.id} zapisana w PostgreSQL (status: ${saved.status})`);}catch(e){console.error('POST /api/bookings:',e);showToast('Błąd','Zapis nieudany: '+e.message,'error');return;}document.getElementById('guest-name').value='';document.getElementById('guest-email').value='';document.getElementById('guest-phone').value='';selectedDates=[];await loadBookings();renderCalendar();}
// KROK 5 (Auth): admin widzi pelne dane wszystkich rezerwacji; zwykly rezerwujacy
// wlasne w pelni, a cudze tylko z maske (dane gościa zastrzezone).
function renderAdmin(){const isAdmin=currentUser&&currentUser.role==='admin';document.getElementById('nav-admin-label').textContent=isAdmin?'Admin':'Moje Rezerwacje';document.querySelector('#admin-section h2').textContent=isAdmin?'Panel Administracyjny':'Moje Rezerwacje';document.getElementById('admin-password-card')?.classList.toggle('hidden',!isAdmin);document.getElementById('stat-bookings').textContent=bookings.length;const revenue=bookings.filter(b=>!b.masked).reduce((sum,b)=>sum+(b.totalPrice||0),0);document.getElementById('stat-revenue').textContent=revenue.toLocaleString()+' zł';document.getElementById('stat-kafka').textContent=Object.values(kafkaTopics).reduce((a,b)=>a+b,0).toLocaleString('pl-PL');['bookings-created','email-invoices','marketing-actions'].forEach(t=>{const el=document.getElementById('topic-'+t);if(el)el.textContent=(kafkaTopics[t]||0).toLocaleString('pl-PL');});document.getElementById('stat-occupancy').textContent=Math.min(95,bookings.length*5)+'%';const tbody=document.getElementById('bookings-table');tbody.innerHTML=bookings.map(b=>{const guest=b.masked?`<i class="fas fa-user-lock text-gray-500 mr-1"></i><span class="text-gray-400">Zastrzeżone (dane gościa ukryte)</span>`:`${b.guestName}<br><span class="text-xs text-gray-500">${b.email}</span>${b.mine?'<span class="ml-2 text-xs px-2 py-0.5 rounded bg-blue-500/20 text-blue-300">Moja rezerwacja</span>':''}`;const price=b.masked?'<span class="text-gray-500">—</span>':`${(b.totalPrice||0).toLocaleString('pl-PL')} zł`;return `<tr class="border-b border-white/5"><td class="py-4 font-mono text-sm text-blue-400">${b.id}</td><td class="py-4">${b.propertyName}</td><td class="py-4">${guest}</td><td class="py-4 text-sm">${b.checkIn} → ${b.checkOut}<br><span class="text-xs text-gray-500">${b.nights} nocy</span></td><td class="py-4 font-bold">${price}</td><td class="py-4"><span class="px-2 py-1 rounded text-xs ${b.status==='confirmed'?'bg-green-500/20 text-green-400':'bg-yellow-500/20 text-yellow-400'}">${b.status}</span></td></tr>`;}).join('')||'<tr><td colspan="6" class="py-8 text-center text-gray-500">Brak rezerwacji w PostgreSQL</td></tr>';}
function exportBookings(){const csv='ID,Nieruchomość,Gość,Email,Check-in,Check-out,Nocy,Kwota,Status\\n'+bookings.map(b=>`${b.id},${b.propertyName},${b.masked?'ZASTRZEŻONE':b.guestName},${b.masked?'':b.email},${b.checkIn},${b.checkOut},${b.nights},${b.masked?'':b.totalPrice},${b.status}`).join('\\n');const blob=new Blob([csv],{type:'text/csv'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='rezerwacje-davtro.csv';a.click();showToast('Eksport','Plik CSV pobrany');}
// KROK 5 (Auth): logowanie / rejestracja / wylogowanie rezerwujacego.
let authMode='login';
function switchAuthTab(mode){authMode=mode;document.getElementById('tab-login').className='flex-1 py-2 rounded-lg font-semibold '+(mode==='login'?'bg-blue-600':'bg-white/10');document.getElementById('tab-register').className='flex-1 py-2 rounded-lg font-semibold '+(mode==='register'?'bg-blue-600':'bg-white/10');document.getElementById('register-fields').classList.toggle('hidden',mode!=='register');document.getElementById('auth-submit').textContent=mode==='login'?'Zaloguj się':'Zarejestruj się i zaloguj';}
async function submitAuth(){const username=document.getElementById('auth-username').value.trim();const password=document.getElementById('auth-password').value;if(!username||!password){showToast('Błąd','Podaj login i hasło','error');return;}const body={username,password};if(authMode==='register'){body.full_name=document.getElementById('auth-fullname').value.trim()||null;body.email=document.getElementById('auth-email').value.trim()||null;}try{const res=await apiJson('/api/auth/'+(authMode==='login'?'login':'register'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});setSession(res.token,res.user);showToast(authMode==='login'?'Zalogowano':'Konto utworzone','Witaj, '+res.user.username+'!');showSection('calendar');}catch(e){showToast('Błąd','Autoryzacja nieudana: '+e.message,'error');}}
function setSession(token,user){authToken=token;currentUser=user;if(token)localStorage.setItem('davtro_token',token);else localStorage.removeItem('davtro_token');updateNav();if(user){document.getElementById('guest-name').value=user.full_name||'';document.getElementById('guest-email').value=user.email||'';}}
function updateNav(){const logged=!!currentUser;document.getElementById('nav-login').classList.toggle('hidden',logged);document.getElementById('nav-user').classList.toggle('hidden',!logged);document.getElementById('nav-user').classList.toggle('flex',logged);document.getElementById('nav-username').textContent=logged?(currentUser.username+(currentUser.role==='admin'?' (admin)':'')):'';}
// KROK 5b: karta zmiany hasla widoczna tylko dla zalogowanych (sekcja Logowanie).
function renderLoginSection(){document.getElementById('password-change').classList.toggle('hidden',!currentUser);}
async function changePassword(){if(!currentUser){showToast('Błąd','Najpierw się zaloguj','error');return;}const cur=document.getElementById('pw-current').value;const neu=document.getElementById('pw-new').value;if(!cur||!neu){showToast('Błąd','Wypełnij oba pola','error');return;}try{const res=await apiJson('/api/auth/change-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({current_password:cur,new_password:neu})});document.getElementById('pw-current').value='';document.getElementById('pw-new').value='';showToast('Gotowe',res.message||'Hasło zmienione');}catch(e){showToast('Błąd','Zmiana hasła nieudana: '+e.message,'error');}}
async function adminSetPassword(){const username=document.getElementById('adm-username').value.trim();const neu=document.getElementById('adm-newpass').value;if(!username||!neu){showToast('Błąd','Podaj login i nowe hasło','error');return;}try{const res=await apiJson('/api/auth/admin/set-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,new_password:neu})});document.getElementById('adm-username').value='';document.getElementById('adm-newpass').value='';showToast('Gotowe',res.message||'Hasło ustawione');}catch(e){showToast('Błąd','Nie udało się: '+e.message,'error');}}
async function logout(){try{await apiJson('/api/auth/logout',{method:'POST'});}catch(e){}setSession(null,null);bookings=[];showToast('Wylogowano','Sesja zakończona','info');showSection('home');}
async function restoreSession(){if(!authToken)return;try{currentUser=await apiJson('/api/auth/me');updateNav();document.getElementById('guest-name').value=currentUser.full_name||'';document.getElementById('guest-email').value=currentUser.email||'';}catch(e){setSession(null,null);}}
// Start: najpierw sesja, potem dane z API (PostgreSQL), potem render strony glownej.
restoreSession().finally(()=>loadProperties().then(()=>{renderFeatured();showSection('home');}));

</script>
</body>
</html>
HTMLEOF

cat > ${PROJECT_NAME}/frontend/Dockerfile << 'EOF'
FROM docker.io/nginxinc/nginx-unprivileged:alpine
# default.conf -> proxy /api (FastAPI) i /kafka-metrics (kafka-exporter)
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
EOF

cat > ${PROJECT_NAME}/frontend/nginx.conf << 'EOF'
# Frontend (nginx-unprivileged) - serwuje SPA i proxuje API oraz metryki Kafki.
# Dzieki temu UI dziala w KAZDYM origin (port-forward 8083, ingress davtro.local,
# localhost) bez CORS i bez hardcode'owanego adresu backendu w JS.
server {
    listen       8080;
    server_name  _;

    root  /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # REST API -> FastAPI (Service w tym samym namespace).
    # Przeplyw rezerwacji: POST /api/bookings (FastAPI robi INSERT do PostgreSQL,
    # SETEX w Redis i produce do Kafki) + GET /api/bookings|/api/properties.
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

    # Realne liczniki topicow Kafki (offsety) -> kafka-exporter (Prometheus metrics).
    # UI parsuje kafka_topic_partition_current_offset i pokazuje prawdziwe liczby
    # zamiast hardcode'owanych 1,247 / 3,892 / 1,198.
    location = /kafka-metrics {
        proxy_pass       http://kafka-exporter:9308/metrics;
        proxy_set_header Host $host;
        proxy_connect_timeout 3s;
        proxy_read_timeout    10s;
    }
}
EOF
truncate -s -1 ${PROJECT_NAME}/frontend/nginx.conf

# ============================================
# FASTAPI BACKEND
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
# KROK 4 (Transit PII): klient HTTP do Vault Transit Engine (app/transit_client.py).
# hvac ciagnie requests tranzytywnie, ale deklarujemy jawnie - to nasza bezposrednia zaleznosc.
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

# KROK 5 (Auth): logowanie rezerwujacych - PBKDF2 (stdlib), sesje w Redis.
from .auth import hash_password, verify_password, new_session_token, SESSION_TTL_SECONDS, generate_random_password

# KROK 4 (Transit PII): szyfrowanie danych wrazliwych (imie, e-mail, telefon)
# przez Vault Transit Engine (key davtro-app). Fail-safe: gdy Vault/Transit sa
# chwilowo niedostepne, logujemy blad i zapisujemy plaintext - API nie pada.
try:
    from .transit_client import decrypt as transit_decrypt
    from .transit_client import encrypt as transit_encrypt

    _TRANSIT_IMPORTED = True
except Exception as _transit_exc:  # pragma: no cover - brak modulu/wersji
    transit_encrypt = None
    transit_decrypt = None
    _TRANSIT_IMPORTED = False
    print("transit_client niedostepny:", _transit_exc)

TRANSIT_ENABLED = os.getenv("VAULT_TRANSIT_ENABLED", "true").lower() in ("1", "true", "yes")
# Ciphertext Vault Transit ma prefiks "vault:vN:" - po nim rozpoznajemy zaszyfrowane pole.
_TRANSIT_PREFIX = "vault:v"

app = FastAPI(title="DavTro Rentals API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

DB_HOST = os.getenv("DB_HOST", "postgres-clusterip")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")
DB_USER_FILE = os.getenv("DB_USER_FILE")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9094")

db_pool = None


def transit_ready():
    """Czy szyfrowanie PII przez Vault Transit jest aktywne."""
    return _TRANSIT_IMPORTED and TRANSIT_ENABLED


def encrypt_pii(value):
    """Szyfruje PII przed zapisem do bazy. Fallback: zwraca plaintext."""
    if value is None or not transit_ready():
        return value
    try:
        return transit_encrypt(str(value))
    except Exception as exc:
        print("encrypt_pii error:", exc)
        return value


def decrypt_pii(value):
    """Deszyfruje PII przy odczycie. Plaintext (stare wiersze) zwraca bez zmian."""
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
    """Odczyt credsyw z pliku montowanego z sekretu ESO (rotowane przez Vault)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return None


def db_creds():
    """Credsy DB: pliki z Vault (database/creds/davtro-app-rw) albo fallback na env."""
    user = (_read_creds_file(DB_USER_FILE) if DB_USER_FILE else None) or os.getenv("DB_USER")
    password = (_read_creds_file(DB_PASSWORD_FILE) if DB_PASSWORD_FILE else None) or os.getenv("DB_PASSWORD")
    if not user or not password:
        raise RuntimeError("Brak credsy DB: oczekiwano DB_USER_FILE/DB_PASSWORD_FILE (Vault/ESO) lub DB_USER/DB_PASSWORD")
    return user, password


# KROK 5b (Auth): haslo admina WYLACZNIE z Vaulta przez ESO (KV davtro/auth ->
# klucz ADMIN_PASSWORD w Secrecie davtro-secrets, ktory deployment juz ma w envFrom)
# albo z pliku ADMIN_PASSWORD_FILE. W repo NIE MA zadnego hasla - gdy Vault go
# nie dostarczy, konto admina dostaje haslo LOSOWE, generowane przy starcie
# (i jednorazowo pokazane w logu), dokladnie jak DB_PASSWORD w bootstrapie.
def admin_password():
    """Zwraca haslo admina z Vaulta/ESO albo None (gdy Vault go nie dostarczyl)."""
    file_path = os.getenv("ADMIN_PASSWORD_FILE")
    from_file = _read_creds_file(file_path) if file_path else None
    return from_file or os.getenv("ADMIN_PASSWORD") or None


def admin_password_or_generated():
    """Haslo z Vaulta; gdy brak - losowe (jednorazowo widoczne w logu)."""
    pwd = admin_password()
    if pwd is not None:
        return pwd
    pwd = generate_random_password()
    print(f"init_db: brak ADMIN_PASSWORD z Vaulta - wygenerowano losowe haslo admina: {pwd}")
    print("init_db: przejmij kontrole nad haslem: vault kv put davtro/auth ADMIN_PASSWORD='<haslo>'")
    return pwd


async def create_db_pool(user, password):
    return await asyncpg.create_pool(
        host=DB_HOST, port=DB_PORT, database=DB_NAME,
        user=user, password=password, min_size=5, max_size=20,
    )


async def watch_db_creds():
    """Rotacja dynamicznych credsyw z Vault: ESO odswieza sekret co refreshInterval,
    kubelet aktualizuje pliki w podzie. Po wykryciu zmiany budujemy nowa pule,
    podmieniamy global (routery i tak czytaja global przy kazdym zapytaniu)
    i zamykamy stara pule."""
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
        except Exception as exc:  # rotacja moze byc chwilowo niedostepna - trzymamy stara pule
            print("watch_db_creds error:", exc)
redis_pool = None
kafka_producer = None

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
    # KROK 5 (Auth): masked=True -> dane gościa (imie/email/telefon/cena) ukryte,
    # bo widz jest zalogowany jako inny uzytkownik (albo niezalogowany).
    masked: bool = False
    # mine=True -> to rezerwacja zalogowanego uzytkownika (odznaka "Moja rezerwacja").
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
    # KROK 11: klient mTLS (confluent-kafka) na listenerze Kafka 9094.
    kafka_producer = get_producer()
    asyncio.create_task(watch_db_creds())
    await init_db()

@app.on_event("shutdown")
async def shutdown():
    if db_pool: await db_pool.close()
    if redis_pool: await redis_pool.close()
    if kafka_producer:
        kafka_producer.flush(5)

async def init_db():
    async with db_pool.acquire() as conn:
        await conn.execute('CREATE TABLE IF NOT EXISTS properties (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, location VARCHAR(100), price DECIMAL(10,2), guests INT DEFAULT 2, description TEXT, amenities JSONB DEFAULT \'[]\', created_at TIMESTAMP DEFAULT NOW())')
        await conn.execute('CREATE TABLE IF NOT EXISTS bookings (id VARCHAR(50) PRIMARY KEY, property_id INT REFERENCES properties(id), guest_name VARCHAR(255), email VARCHAR(255), phone VARCHAR(255), guests INT, user_id INT, username VARCHAR(100), check_in DATE, check_out DATE, nights INT, total_price DECIMAL(10,2), status VARCHAR(50) DEFAULT \'confirmed\', pipeline VARCHAR(100) DEFAULT \'Redis -> Kafka -> PostgreSQL\', created_at TIMESTAMP DEFAULT NOW())')
        # KROK 4 (Transit PII) FIX: szyfrogram Vault Transit ("vault:v1:...") ma ~65-90 znakow,
        # a kolumna phone byla VARCHAR(50) -> kazdy INSERT padal z StringDataRightTruncation.
        # Idempotentna migracja baz utworzonych starsza wersja kodu (no-op, gdy juz 255).
        # ALTER wymaga wlasnosci tabeli, a API laczy sie dynamicznymi credsami z Vaulta
        # (davtro-app-rw: SELECT/INSERT/UPDATE/DELETE, bez ALTER) - dlatego best-effort:
        # brak uprawnien logujemy i dzialamy dalej (swieza baza ma VARCHAR(255) w DDL).
        try:
            await conn.execute("ALTER TABLE bookings ALTER COLUMN phone TYPE VARCHAR(255)")
        except Exception as exc:
            print("init_db: pomijam ALTER bookings.phone (brak wlasnosci tabeli):", exc)
        # KROK 5 (Auth): konta rezerwujacych + powiazanie rezerwacji z kontem
        # (user_id/username), zeby jeden rezerwujacy nie widzial danych drugiego.
        await conn.execute("""CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY, username VARCHAR(100) UNIQUE NOT NULL,
            password_hash TEXT NOT NULL, role VARCHAR(20) NOT NULL DEFAULT 'user',
            full_name VARCHAR(255), email VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW())""")
        # KROK 5 (Auth): kolumny user_id/username sa opcjonalne - aplikacja laczy sie
        # dynamicznymi credsami z Vaulta, ktore moga nie miec prawa ALTER (tabela
        # bookings nalezy do wczesniejszego, wygaslego uzytkownika Vault). API musi
        # wtedy dalej dzialac (bez powiazania rezerwacji z kontem).
        global BOOKINGS_HAS_USER_ID, BOOKINGS_HAS_USERNAME
        for ddl in ("ALTER TABLE bookings ADD COLUMN IF NOT EXISTS user_id INT",
                    "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS username VARCHAR(100)"):
            try:
                await conn.execute(ddl)
            except Exception as exc:
                print("init_db: pomijam", ddl, ":", exc)
        BOOKINGS_HAS_USER_ID = bool(await conn.fetchval(
            "SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='user_id'"))
        BOOKINGS_HAS_USERNAME = bool(await conn.fetchval(
            "SELECT 1 FROM information_schema.columns WHERE table_name='bookings' AND column_name='username'"))
        if not (BOOKINGS_HAS_USER_ID and BOOKINGS_HAS_USERNAME):
            print("init_db: UWAGA - brak kolumn user_id/username w bookings (brak praw ALTER); "
                  "rezerwacje nie beda powiazane z kontami, dopoki tabela nalezy do innego uzytkownika")
        elif await conn.fetchval("SELECT COUNT(*) FROM bookings WHERE user_id IS NULL") > 0:
            # KROK 5b (Backfill): rezerwacje utworzone przed dodaniem kolumn - przypisujemy
            # je do kont po e-mailu gościa (obie strony deszyfrowane Vault Transitem).
            # Bez tego wlasciciel widzialby wlasne rezerwacje jako "Zastrzezone".
            try:
                orphan_rows = await conn.fetch(
                    "SELECT id, email FROM bookings WHERE user_id IS NULL AND email IS NOT NULL")
                user_rows = await conn.fetch("SELECT id, email FROM users WHERE email IS NOT NULL")
                email_to_uid = {}
                for u in user_rows:
                    try:
                        email_to_uid[(decrypt_pii(u["email"]) or "").strip().lower()] = u["id"]
                    except Exception:
                        continue
                linked = 0
                for b in orphan_rows:
                    try:
                        b_email = (decrypt_pii(b["email"]) or "").strip().lower()
                    except Exception:
                        continue
                    uid = email_to_uid.get(b_email)
                    if uid is not None:
                        await conn.execute(
                            """UPDATE bookings SET user_id=$1,
                                   username=(SELECT username FROM users WHERE id=$1)
                               WHERE id=$2""", uid, b["id"])
                        linked += 1
                if linked:
                    print(f"init_db: backfill - przypisano {linked} rezerwacji do kont (po e-mailu)")
            except Exception as exc:
                print("init_db: backfill rezerwacji pominiony:", exc)
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
        # KROK 5 (Auth): konto administratora (widzi wszystkie dane gości).
        # Seed per-username: dziala tez, gdy tabela users ma juz innych uzytkownikow
        # (np. po uruchomieniu starszej wersji aplikacji bez seeda admina).
        admin_user = os.getenv("ADMIN_USERNAME", "admin")
        # KROK 5b: haslo WYLACZNIE z Vaulta; gdy Vault go nie dostarczyl -
        # losowe generowane przy starcie (jedyne miejsce, gdzie je widać: log startu).
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
    return {"status": "healthy", "database": db_ok == 1, "redis": redis_ok, "kafka": kafka_producer is not None, "transit": transit_ready()}

@app.get("/api/properties")
async def get_properties():
    cache_key = "properties:all"
    cached = await redis_pool.get(cache_key)
    if cached: return json.loads(cached)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM properties ORDER BY id")
    properties = [{"id": r["id"], "name": r["name"], "location": r["location"], "price": float(r["price"]), "guests": r["guests"], "description": r["description"], "amenities": json.loads(r["amenities"])} for r in rows]
    await redis_pool.setex(cache_key, 300, json.dumps(properties))
    return properties

# KROK 5 (Auth): sesje trzymane w Redis (session:<token>, TTL 24h).
SESSION_KEY_PREFIX = "session:"
# Czy tabela bookings ma kolumny powiazania z kontem (wykrywane w init_db - kolumny
# moga nie istniec, gdy brak praw ALTER do tabeli utworzonej przez innego uzytkownika).
BOOKINGS_HAS_USER_ID = True
BOOKINGS_HAS_USERNAME = True


async def get_current_user(request: Request) -> Optional[AuthUser]:
    """Odczytuje usera z naglowka Authorization: Bearer <token> (Redis)."""
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
    """Rezerwacja wymaga zalogowania (KROK 5)."""
    user = await get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Wymagane zalogowanie")
    return user


def is_admin(user: Optional[AuthUser]) -> bool:
    return user is not None and user.role == "admin"


def owns_booking(user: Optional[AuthUser], row_user_id) -> bool:
    """Wlasciciel rezerwacji (albo admin) widzi pelne dane; inni - tylko maske."""
    if user is None:
        return False
    if user.role == "admin":
        return True
    return row_user_id is not None and int(row_user_id) == int(user.id)

# Wartosci zwracane dla "obcych" rezerwacji - dane gościa sa zastrzezone.
MASKED_GUEST_NAME = "Zastrzeżone (dane gościa ukryte)"


@app.post("/api/auth/register")
async def register_user(payload: RegisterRequest):
    """Rejestracja rezerwujacego + natychmiastowy login (token do Redisa)."""
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
    """Login/haslo -> token sesyjny w Redis (Authorization: Bearer)."""
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM users WHERE username=$1", payload.username.strip())
        # Bootstrap-awaryjny: brak konta admina (np. seed nie przeszedl przy pierwszym
        # starcie starszej wersji) -> tworzymy je z ADMIN_PASSWORD przy probie logowania.
        if row is None and payload.username.strip() == os.getenv("ADMIN_USERNAME", "admin"):
            admin_user = payload.username.strip()
            await conn.execute(
                "INSERT INTO users (username, password_hash, role) VALUES ($1,$2,'admin') ON CONFLICT (username) DO NOTHING",
                admin_user, hash_password(admin_password_or_generated()))
            print(f"login: bootstrap konta admina '{admin_user}' (brak konta przy logowaniu)")
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
    """Zmiana wlasnego hasla - wymaga aktualnego hasla (KROK 5b)."""
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
    """Tylko admin: reset hasla dowolnego uzytkownika (KROK 5b)."""
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
    # KROK 5 (Auth): rezerwacja wymaga zalogowania - inaczej nie da sie ukryc
    # danych gościa przed innymi rezerwujacymi.
    user = await require_user(request)
    booking_id = f"BK-{datetime.now().strftime('%Y%m%d%H%M%S')}-{booking.property_id}"
    nights = (booking.check_out - booking.check_in).days
    cache_key = f"booking:{booking_id}"
    # FIX: booking.dict() zostawial obiekty datetime.date, na ktorych json.dumps()
    # rzucal TypeError ("Object of type date is not JSON serializable") -> 500.
    # model_dump(mode="json") konwertuje date na ISO-8601 (str), wiec SETEX do Redisa
    # i events do Kafki przechodza bez zmian w przeplywie.
    booking_data = booking.model_dump(mode="json")
    booking_data.update({"id": booking_id, "nights": nights, "status": "pending"})
    # KROK 4 (Transit PII): dane osobowe (imie, e-mail, telefon) zapisujemy do
    # PostgreSQL zaszyfrowane kluczem Vault Transit (key davtro-app). Kafka i Redis
    # dostaja plaintext, bo message-processor wysyla z niego e-maile.
    async with db_pool.acquire() as conn:
        # KROK 5: powiazanie rezerwacji z kontem tylko gdy kolumny istnieja
        # (gdy brak praw ALTER do tabeli zapisujemy bez user_id/username).
        if BOOKINGS_HAS_USER_ID and BOOKINGS_HAS_USERNAME:
            await conn.execute(
                """INSERT INTO bookings (id, property_id, guest_name, email, phone, guests, user_id, username,
                       check_in, check_out, nights, total_price, status)
                   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
                   ON CONFLICT (id) DO NOTHING""",
                booking_id, booking.property_id,
                encrypt_pii(booking.guest_name), encrypt_pii(booking.email), encrypt_pii(booking.phone),
                booking.guests, user.id, user.username, booking.check_in, booking.check_out, nights,
                booking.total_price, "pending",
            )
        else:
            await conn.execute(
                """INSERT INTO bookings (id, property_id, guest_name, email, phone, guests,
                       check_in, check_out, nights, total_price, status)
                   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
                   ON CONFLICT (id) DO NOTHING""",
                booking_id, booking.property_id,
                encrypt_pii(booking.guest_name), encrypt_pii(booking.email), encrypt_pii(booking.phone),
                booking.guests, booking.check_in, booking.check_out, nights,
                booking.total_price, "pending",
            )
    await redis_pool.setex(cache_key, 3600, json.dumps(booking_data))
    publish_event("bookings-created", {"event": "booking_created", "booking_id": booking_id, "property_id": booking.property_id, "guest_name": booking.guest_name, "email": booking.email, "phone": booking.phone, "check_in": str(booking.check_in), "check_out": str(booking.check_out), "nights": nights, "total_price": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    publish_event("email-invoices", {"event": "invoice_request", "booking_id": booking_id, "email": booking.email, "guest_name": booking.guest_name, "total_price": float(booking.total_price), "property_id": booking.property_id, "check_in": str(booking.check_in), "check_out": str(booking.check_out)})
    publish_event("marketing-actions", {"event": "new_booking", "property_id": booking.property_id, "guest_email": booking.email, "guest_name": booking.guest_name, "booking_value": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    return BookingResponse(id=booking_id, property_id=booking.property_id, property_name="", guest_name=booking.guest_name, email=booking.email, check_in=str(booking.check_in), check_out=str(booking.check_out), total_price=booking.total_price, status="pending", created_at=datetime.now().isoformat())

@app.get("/api/bookings")
async def get_bookings(request: Request, property_id: Optional[int] = None):
    """KROK 5 (Auth): wlasciciel rezerwacji i admin widza pelne dane gościa
    (imie, email, telefon, kwote). Pozostali dostaja wiersz zamaskowany -
    w kolach kalendarza daty zostaja, bo potrzebne do pokazania dostepnosci."""
    user = await get_current_user(request)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT b.*, p.name as property_name FROM bookings b JOIN properties p ON b.property_id = p.id WHERE ($1::int IS NULL OR b.property_id = $1::int) ORDER BY b.created_at DESC",
            property_id)
    result = []
    for r in rows:
        # .get() - kolumna user_id moze nie istniec w starszej tabeli bookings
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

cat > ${PROJECT_NAME}/backend-fastapi/app/db.py << 'EOF'
import os
import threading
from sqlalchemy import create_engine, Column, Integer, String, Numeric, Date, Boolean, DateTime, func
from sqlalchemy.orm import declarative_base, sessionmaker

DB_HOST = os.getenv("DB_HOST", "postgres-clusterip")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")

# KROK 3: dynamiczne credsy z Vault (database/creds/davtro-app-rw) dostarczane przez ESO.
# Sekret montowany jest jako PLIKI (DB_USER_FILE / DB_PASSWORD_FILE); kubelet odswieza
# montaz po rotacji, a get_engine() przebudowuje silnik po wykryciu zmiany tresci.
# Fallback dla dev lokalnego: DB_USER/DB_PASSWORD z env albo pelny DATABASE_URL.
DB_USER_FILE = os.getenv("DB_USER_FILE")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE")
DATABASE_URL = os.getenv("DATABASE_URL")  # tylko dev lokalny (statyczne credsy)


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
        raise RuntimeError(
            "Brak credsy DB: oczekiwano DB_USER_FILE/DB_PASSWORD_FILE (Vault/ESO) "
            "lub DB_USER/DB_PASSWORD/DATABASE_URL (dev lokalny)"
        )
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
    """Sesja zwiazana z AKTUALNYM silnikiem - po rotacji credsyw z Vaulta
    kolejne wywolania lacza sie juz nowym, tymczasowym uzytkownikiem."""
    return sessionmaker(bind=get_engine(), autoflush=False, autocommit=False)()


SessionLocal = get_session  # zgodnosc wstecz (consumer.py)
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
    body = (
        f"Cześć {guest_name},\n\n"
        f"Twoja rezerwacja ({event['date_from']} - {event['date_to']}) została potwierdzona.\n"
        f"W załączeniu (proforma) prosimy o dokonanie płatności przed przyjazdem.\n\n"
        f"Pozdrawiamy,\nDavtro Apartments"
    )
    _send(to_email, subject, body)


def send_marketing_email(to_email: str, guest_name: str):
    subject = "Sprawdź nasze najnowsze oferty!"
    body = f"Cześć {guest_name}, mamy dla Ciebie nowe promocje na pobyty krótkoterminowe."
    _send(to_email, subject, body)
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/kafka_producer.py << 'EOF'
import json
import os
from confluent_kafka import Producer

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9094")
_producer = None


def get_producer():
    global _producer
    if _producer is None:
        _producer = Producer({
            "bootstrap.servers": KAFKA_BOOTSTRAP,
            "security.protocol": "SSL",
            "ssl.ca.location": os.getenv("KAFKA_CA_FILE", "/etc/kafka-tls/ca.crt"),
            "ssl.certificate.location": os.getenv("KAFKA_TLS_CERT_FILE", "/etc/kafka-tls/tls.crt"),
            "ssl.key.location": os.getenv("KAFKA_TLS_KEY_FILE", "/etc/kafka-tls/tls.key"),
            "ssl.endpoint.identification.algorithm": "https",
        })
    return _producer


def publish_event(topic: str, event: dict):
    producer = get_producer()
    producer.produce(topic, json.dumps(event).encode("utf-8"))
    producer.flush(5)
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/consumer.py << 'EOF'
"""
message-processor: osobny deployment/consumer.
Czyta z tematow Kafka 'bookings-created' i 'marketing-actions',
wysyla e-mail (potwierdzenie + faktura proforma) i aktualizuje status w Postgresql.
Kolejka Redis sluzy do deduplikacji/idempotencji przetwarzania.
"""
import json
import os

import redis
from confluent_kafka import Consumer

from .db import SessionLocal, Booking
from .email_sender import send_confirmation_email, send_marketing_email

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9094")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def handle_booking_event(event: dict):
    dedup_key = f"processed:{event.get('event_id', event.get('booking_id', 'unknown'))}"
    if redis_client.get(dedup_key):
        return
    send_confirmation_email(event.get("email", event.get("guest_email")), event.get("guest_name", "Gosc"), event)

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
    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": "message-processor",
        "auto.offset.reset": "earliest",
        "security.protocol": "SSL",
        "ssl.ca.location": os.getenv("KAFKA_CA_FILE", "/etc/kafka-tls/ca.crt"),
        "ssl.certificate.location": os.getenv("KAFKA_TLS_CERT_FILE", "/etc/kafka-tls/tls.crt"),
        "ssl.key.location": os.getenv("KAFKA_TLS_KEY_FILE", "/etc/kafka-tls/tls.key"),
        "ssl.endpoint.identification.algorithm": "https",
    })
    consumer.subscribe(["bookings-created", "marketing-actions"])
    print("message-processor: nasluchiwanie na bookings-created i marketing-actions...")
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

cat > ${PROJECT_NAME}/backend-fastapi/app/auth.py << 'EOF'
"""
KROK 5 (Auth): logowanie rezerwujacych - hashowanie hasel PBKDF2 (stdlib,
bez nowych zaleznosci) i generowanie tokenow sesyjnych (przechowywane w Redis).

Uzycie:
    from .auth import hash_password, verify_password, new_session_token

    pwd_hash = hash_password("tajne")
    assert verify_password("tajne", pwd_hash)
"""

import hashlib
import hmac
import secrets

PBKDF2_ITERATIONS = 260_000
SALT_BYTES = 16
SESSION_TOKEN_BYTES = 32
SESSION_TTL_SECONDS = 86_400  # 24h


def hash_password(password: str) -> str:
    """PBKDF2-HMAC-SHA256; format: pbkdf2_sha256$<iter>$<salt_hex>$<hash_hex>."""
    salt = secrets.token_bytes(SALT_BYTES)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS
    )
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    """Stale-time porownanie; zwraca False przy uszkodzonym formacie."""
    try:
        algo, iterations, salt_hex, hash_hex = stored.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            bytes.fromhex(salt_hex),
            int(iterations),
        )
        return hmac.compare_digest(digest.hex(), hash_hex)
    except (ValueError, TypeError):
        return False


def new_session_token() -> str:
    """Token sesyjny do przechowania w Redis (klucz session:<token>, TTL 24h)."""
    return secrets.token_urlsafe(SESSION_TOKEN_BYTES)


def generate_random_password(length: int = 24) -> str:
    """Losowe haslo admina generowane przy starcie, gdy Vault nie dostarczyl
    ADMIN_PASSWORD (dokladnie jak DB_PASSWORD generowane przez bootstrap)."""
    return secrets.token_urlsafe(max(16, min(length, 64)))
EOF

cat > ${PROJECT_NAME}/backend-fastapi/app/transit_client.py << 'EOF'
#!/usr/bin/env python3
"""
KROK 4 (Transit PII): Vault Transit Engine client dla aplikacji Python.
Szyfruje/deszyfruje wrazliwe dane (PII, telefony, e-maile) przed zapisem do bazy.

Vault zarzadza kluczem KEK (transit/keys/davtro-app, auto-rotate 30 dni),
aplikacja nie widzi klucza - wysyla plaintext do Vaulta i dostaje ciphertext
("vault:v1:..."). Token do Vaulta pobierany przez Kubernetes auth
(role davtro-transit, SA davtro-sa, ttl 1h) i odswiezany po wygasnieciu.

Uzycie:
    from .transit_client import encrypt, decrypt

    ciphertext = encrypt("Jan Kowalski, +48 123 456 789")
    plaintext = decrypt(ciphertext)
"""

import base64
import logging
import os
import time
from typing import Dict, Optional, Tuple

import requests

logger = logging.getLogger(__name__)

# Token z K8s auth ma ttl=1h - odswiezamy z zapasem, zeby nie trafic na 403.
TOKEN_TTL_SECONDS = 3000

# KROK 9/10 (Vault HTTPS): CA bootstrapowego cert-managera (Issuer vault-ca ->
# sekret `vault-tls` montowany w podach). To samo CA ufa Vaultowi w ESO
# (caProvider) i w helmowym `vault status`.
DEFAULT_VAULT_CA_FILE = "/etc/vault-tls/ca.crt"
# Login robi TokenReview na apiserverze - kilka sekund to norma, 10s bywalo za malo.
DEFAULT_VAULT_TIMEOUT = 30


def vault_tls_config() -> Tuple[str, object]:
    """Adres Vaulta + weryfikacja TLS w JEDNYM miejscu (KROK 9/10).

    FIX: wczesniej `verify` przekazywalo TYLKO `TransitClient._request()`, a
    `VaultTokenProvider.get_token()` wolalo `requests.post()` bez `verify` -
    czyli uzywalo systemowego store CA. Cert serwera Vaulta pochodzi z
    wewnetrznego CA (`davtro-vault-ca`), wiec LOGIN do
    `auth/kubernetes/login` padal z:
        SSLError(... CERTIFICATE_VERIFY_FAILED ... unable to get local issuer certificate)

    Skutek awarii: brak tokena -> `encrypt_pii()` i `decrypt_pii()` (main.py)
    zawsze wracaly z fallbacku, czyli:
      * w panelu "Moje Rezerwacje" wlasciciel widzial surowy ciphertext
        `vault:v1:...` zamiast swojego imienia/e-maila,
      * nowe rezerwacje zapisywaly sie w PostgreSQL jako plaintext (dane PII).
    """
    scheme = os.environ.get("VAULT_TRANSIT_SCHEME", "https")
    addr = os.environ.get("VAULT_TRANSIT_ADDR") or f"{scheme}://vault.davtro02.svc.cluster.local:8203"
    ca_file = os.environ.get("VAULT_TRANSIT_CA_FILE", DEFAULT_VAULT_CA_FILE)
    if ca_file and os.path.exists(ca_file):
        return addr, ca_file
    if scheme == "https":
        logger.warning(
            "Vault: brak pliku CA '%s' - spadam na systemowy store CA; przy wewnetrznym "
            "CA Vaulta kazde polaczenie (login i transit) padnie z "
            "CERTIFICATE_VERIFY_FAILED (KROK 9). Ustaw VAULT_TRANSIT_CA_FILE.",
            ca_file,
        )
        return addr, True
    # HTTP (dev/port-forward bez TLS): nie ma czego weryfikowac.
    return addr, False


class VaultTokenProvider:
    """Pobiera token Vault przez Kubernetes auth (z cache i auto-renew)."""

    def __init__(self, vault_addr: Optional[str] = None, verify=None,
                 timeout: Optional[int] = None):
        default_addr, default_verify = vault_tls_config()
        self.vault_addr = vault_addr or default_addr
        # FIX (KROK 9/10): ten sam `verify` co dla transit/* - bez tego login do
        # Vaulta szedl po systemowym CA i wszystko konczylo sie fallbackiem.
        self.verify = default_verify if verify is None else verify
        self.auth_role = os.environ.get(
            "VAULT_TRANSIT_AUTH_ROLE",
            "davtro-transit",
        )
        self.timeout = timeout or int(
            os.environ.get("VAULT_TRANSIT_TIMEOUT", DEFAULT_VAULT_TIMEOUT)
        )
        self._token: Optional[str] = None
        self._token_expiry: float = 0.0

    def get_token(self, renew: bool = False) -> str:
        """Zwraca wazny token Vault; renew=True wymusza ponowny login."""
        if self._token and not renew and time.time() < self._token_expiry:
            return self._token

        sa_token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        with open(sa_token_path, "r") as f:
            sa_token = f.read().strip()

        url = f"{self.vault_addr}/v1/auth/kubernetes/login"
        payload = {"jwt": sa_token, "role": self.auth_role}

        try:
            resp = requests.post(
                url, json=payload, timeout=self.timeout, verify=self.verify
            )
        except requests.RequestException as exc:
            # Najczestsza przyczyna: brak/zly CA dla wewnetrznego CA Vaulta.
            logger.error(
                "Vault login failed (%s, CA=%s): %s", url, self.verify, exc
            )
            raise
        resp.raise_for_status()
        auth = resp.json()["auth"]
        self._token = auth["client_token"]
        lease = int(auth.get("lease_duration") or 3600)
        # Odswiezamy minute przed wygasnieciem, ale nie pozniej niz TOKEN_TTL_SECONDS.
        self._token_expiry = time.time() + max(60, min(lease - 60, TOKEN_TTL_SECONDS))
        return self._token


class TransitClient:
    """Client dla Vault Transit Engine."""

    def __init__(self, key_name: Optional[str] = None):
        # KROK 9/10 (Vault HTTPS): adres + CA z jednego miejsca (vault_tls_config).
        self.vault_addr, self.verify = vault_tls_config()
        self.key_name = key_name or os.environ.get("VAULT_TRANSIT_KEY", "davtro-app")
        self.timeout = int(
            os.environ.get("VAULT_TRANSIT_TIMEOUT", DEFAULT_VAULT_TIMEOUT)
        )
        # FIX (KROK 9/10): token provider dostaje ten sam `verify` - wczesniej
        # logowal sie po systemowym store CA i nie mogl wystawic tokena,
        # przez co encrypt/decrypt zawsze konczyly sie fallbackiem.
        self.token_provider = VaultTokenProvider(self.vault_addr, self.verify)
        self._session = requests.Session()

    def _request(self, path: str, payload: Dict[str, str]) -> Dict:
        """POST do Vaulta z auto-renew tokena przy 403 (token wygasl)."""
        url = f"{self.vault_addr}/v1/{path}"
        for attempt in (1, 2):
            try:
                token = self.token_provider.get_token(renew=(attempt == 2))
            except Exception as exc:
                logger.error("Vault auth failed: %s", exc)
                raise
            resp = self._session.post(
                url, json=payload, headers={"X-Vault-Token": token},
                timeout=self.timeout, verify=self.verify,
            )
            if resp.status_code == 403 and attempt == 1:
                logger.warning("Vault 403 - odswiezam token i ponawiam")
                continue
            resp.raise_for_status()
            return resp.json()["data"]
        raise RuntimeError("Vault transit: nieudana autoryzacja po renew tokena")

    def encrypt(self, plaintext: str) -> str:
        """Szyfruje dane przez Vault Transit Engine."""
        b64_plaintext = base64.b64encode(str(plaintext).encode()).decode()
        data = self._request(
            f"transit/encrypt/{self.key_name}", {"plaintext": b64_plaintext}
        )
        return data["ciphertext"]

    def decrypt(self, ciphertext: str) -> str:
        """Deszyfruje dane z Vault Transit Engine."""
        data = self._request(
            f"transit/decrypt/{self.key_name}", {"ciphertext": ciphertext}
        )
        return base64.b64decode(data["plaintext"]).decode()

    def encrypt_dict(self, data: Dict[str, str]) -> Dict[str, str]:
        """Szyfruje wartosci w slowniku."""
        return {k: self.encrypt(v) for k, v in data.items()}

    def decrypt_dict(self, data: Dict[str, str]) -> Dict[str, str]:
        """Deszyfruje wartosci w slowniku."""
        return {k: self.decrypt(v) for k, v in data.items()}


# Globalna instancja (lazy init)
_transit_client: Optional[TransitClient] = None


def get_transit_client() -> TransitClient:
    """Zwraca globalna instancje TransitClient."""
    global _transit_client
    if _transit_client is None:
        _transit_client = TransitClient()
    return _transit_client


# Helper functions dla wygodnego uzycia
def encrypt(plaintext: str) -> str:
    """Szyfruje dane przez Vault Transit Engine."""
    return get_transit_client().encrypt(plaintext)


def decrypt(ciphertext: str) -> str:
    """Deszyfruje dane z Vault Transit Engine."""
    return get_transit_client().decrypt(ciphertext)
EOF

# ============================================
# SPRING BOOT BACKEND
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

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental
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

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/model
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

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/repository
cat > ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/repository/BookingRepository.java << 'EOF'
package com.davtro.rental.repository;
import com.davtro.rental.model.Booking;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
@Repository
public interface BookingRepository extends JpaRepository<Booking, String> {}
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/consumer
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
            booking.setPipeline("Redis -> Kafka -> PostgreSQL");
            booking.setCreatedAt(LocalDateTime.now());
            bookingRepository.save(booking);
            log.info("Booking saved: {}", booking.getId());
        } catch (Exception e) { log.error("Error: {}", e.getMessage()); }
    }
    @KafkaListener(topics = "email-invoices", groupId = "spring-app-group")
    public void consumeInvoice(String message) {
        try {
            JsonNode json = objectMapper.readTree(message);
            emailService.sendProformaInvoice(json.get("email").asText(), json.get("guest_name").asText(), json.get("booking_id").asText(), new BigDecimal(json.get("total_price").asText()));
        } catch (Exception e) { log.error("Error sending invoice: {}", e.getMessage()); }
    }
}
EOF

mkdir -p ${PROJECT_NAME}/java-app/src/main/java/com/davtro/rental/service
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
            message.setText(String.format("Witaj %s!\n\nTwoja rezerwacja zostala potwierdzona.\nNumer: %s\nKwota: %s zl\n\nFaktura proforma. Prosze o platnosc w terminie 24h.\n\nPozdrawiamy,\nZespol DavTro Rentals", guestName, bookingId, total.toString()));
            mailSender.send(message);
            log.info("Proforma sent to: {}", to);
        } catch (Exception e) { log.error("Failed to send: {}", e.getMessage()); }
    }
}
EOF

cat > ${PROJECT_NAME}/java-app/src/main/resources/application.properties << 'EOF'
server.port=8081
# HOST: postgres-clusterip (Service) - wczesniej bledny default 'postgres-db'
spring.datasource.url=jdbc:postgresql://${DB_HOST:postgres-clusterip}:5432/davtro_rentals
# Credsy na razie statyczne z KV (davtro-secrets przez ESO); brak defaultu = fail-fast.
# Migracja na dynamiczne credsy: Spring Cloud Vault (Krok 4 planu).
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}
spring.jpa.hibernate.ddl-auto=validate
spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP:kafka-kraft:9094}
spring.kafka.consumer.group-id=spring-app-group
spring.kafka.consumer.auto-offset-reset=earliest
# KROK 11: klient Kafka po mTLS. Kafka 3.x akceptuje PEM bez konwersji do JKS.
spring.kafka.properties.security.protocol=SSL
spring.kafka.properties.ssl.enabled=true
spring.kafka.properties.ssl.endpoint.identification.algorithm=https
spring.kafka.properties.ssl.keystore.type=PEM
spring.kafka.properties.ssl.keystore.certificate.chain.file=${KAFKA_TLS_CERT_FILE:/etc/kafka-tls/tls.crt}
spring.kafka.properties.ssl.keystore.key.file=${KAFKA_TLS_KEY_FILE:/etc/kafka-tls/tls.key}
spring.kafka.properties.ssl.truststore.type=PEM
spring.kafka.properties.ssl.truststore.certificates.file=${KAFKA_CA_FILE:/etc/kafka-tls/ca.crt}
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

mkdir -p ${PROJECT_NAME}/spark-jobs/project
cat > ${PROJECT_NAME}/spark-jobs/project/plugins.sbt << 'EOF'
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.1.5")
EOF

cat > ${PROJECT_NAME}/spark-jobs/project/build.properties << 'EOF'
sbt.version=1.10.7
EOF

mkdir -p ${PROJECT_NAME}/spark-jobs/src/main/scala/com/davtro/jobs
cat > ${PROJECT_NAME}/spark-jobs/src/main/scala/com/davtro/jobs/MarketingAnalyticsJob.scala << 'EOF'
package com.davtro.jobs
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.streaming.Trigger
object MarketingAnalyticsJob {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder().appName("DavTro Marketing Analytics").master("spark://spark-master:7077").config("spark.sql.streaming.checkpointLocation", "/tmp/checkpoint").getOrCreate()
    import spark.implicits._
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
# KUBERNETES MANIFESTS (Base)
# ============================================

cat > ${PROJECT_NAME}/manifests/base/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: davtro
  labels:
    app.kubernetes.io/part-of: davtro-platform
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
  name: kafka-job-sa
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
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9094"
EOF

cat > ${PROJECT_NAME}/manifests/base/secret.yaml << 'EOF'
# STARY statyczny sekret USUNIETY z deployu (Krok 2: Vault + External Secrets Operator).
# Sekrety teraz: Vault KV (mount 'davtro') -> ESO (secret-store.yaml, external-secrets.yaml)
#                -> Secret davtro-secrets (generowany w klastrze).
# Jawnie wpisane hasla nie moga byc w Git - stary plik z wartosciami jest tylko
# w historii gita (PO PROSTU ich nie uzywaj - stare haslo bylo publiczne).
# Po skonfigurowaniu Vaulta + instalacji ESO ArgoCD (prune: true) usunie stary
# sekret z klastra, a ESO odtworzy go z Vaulta w tym samym ksztalcie kluczy.
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
      serviceAccountName: davtro-sa
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      volumes:
        - { name: db-creds, secret: { secretName: fastapi-db-creds } }
        - { name: transit-helpers, configMap: { name: transit-helpers } }
        # optional: cert vault-tls wystawia cert-manager dopiero po starcie Vaulta
        # (klero-wajka) - bez tego nowe pody utykaja w ContainerCreating.
        - { name: vault-tls, secret: { secretName: vault-tls, optional: true } }
        - { name: fastapi-mtls, secret: { secretName: fastapi-mtls } }
      containers:
        - name: fastapi
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02:latest
          ports: [{ containerPort: 8080 }]
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
          env:
            # Dynamiczne credsy DB z Vaulta (database/creds/davtro-app-rw, rotowane co 30m).
            # Env nadpisuje wartosci z envFrom; pliki z sekretu ESO odswieza kubelet,
            # aplikacja przeladowuje pule polaczen przy wykryciu zmiany (main.py watch_db_creds).
            - { name: DB_USER_FILE, value: /etc/db-creds/username }
            - { name: DB_PASSWORD_FILE, value: /etc/db-creds/password }
            # KROK 9 (Vault HTTPS): transit po TLS z CA davtro-internal
            - { name: VAULT_TRANSIT_ADDR, value: "https://vault.davtro02.svc.cluster.local:8203" }
            - { name: VAULT_TRANSIT_CA_FILE, value: "/etc/vault-tls/ca.crt" }
            - { name: VAULT_TRANSIT_KEY, value: "davtro-app" }
            - { name: VAULT_TRANSIT_AUTH_ROLE, value: "davtro-transit" }
            - { name: KAFKA_TLS_CERT_FILE, value: "/etc/mtls/tls.crt" }
            - { name: KAFKA_TLS_KEY_FILE, value: "/etc/mtls/tls.key" }
            - { name: KAFKA_CA_FILE, value: "/etc/mtls/ca.crt" }
            # KROK 6 (mTLS): certyfikaty klienta
            - { name: MTLS_CERT_FILE, value: "/etc/mtls/tls.crt" }
            - { name: MTLS_KEY_FILE, value: "/etc/mtls/tls.key" }
            - { name: MTLS_CA_FILE, value: "/etc/mtls/ca.crt" }
          volumeMounts:
            - { name: db-creds, mountPath: /etc/db-creds, readOnly: true }
            - { name: transit-helpers, mountPath: /usr/local/bin/transit, readOnly: true }
            - { name: vault-tls, mountPath: /etc/vault-tls, readOnly: true }
            - { name: fastapi-mtls, mountPath: /etc/mtls, readOnly: true }
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
      serviceAccountName: davtro-sa
      containers:
        - name: nginx
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-frontend:latest
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
      securityContext:
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
        fsGroupChangePolicy: OnRootMismatch
      initContainers:
        # microk8s-hostpath nie stosuje fsGroup - katalog PV zostaje root:root,
        # przez co initdb (uid 999) nie moze zrobic chmod. Ten initContainer
        # (celowo jako root) nadaje wlasciciela przed startem postgres.
        - name: fix-data-permissions
          image: postgres:16-alpine
          command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data"]
          securityContext:
            runAsUser: 0
            runAsGroup: 0
            # celowo root: nadpisuje runAsNonRoot z poziomu poda,
            # inaczej kubelet odrzuca initContainer ("breaks non-root policy")
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
# Vault - storage raft na PV, API wyłącznie przez TLS (:8203), UI i telemetria.
# Cert `vault-tls` jest wystawiany przez bootstrapowe CA cert-managera
# (`vault-server-tls.yaml`) i MUSI istnieć przed uruchomieniem poda. Nie ma już
# fallbacku HTTP :8200 — brak certyfikatu oznacza oczekiwanie kubeleta, nie
# uruchomienie niezabezpieczonego API.
#
# RUNBOOK pierwszego uruchomienia (jednorazowo):
#   kubectl -n davtro02 port-forward vault-0 8243:8203 &
#   export VAULT_ADDR=https://127.0.0.1:8243
#   kubectl -n davtro02 get secret vault-tls -o jsonpath='{.data.ca\.crt}' \
#     | base64 -d > /tmp/vault-ca.crt
#   export VAULT_CACERT=/tmp/vault-ca.crt
#   vault operator init -key-shares=1 -key-threshold=1
#     -> zapisz unseal_key i root_token POZA repozytorium (menedzer hasel)!
#   vault operator unseal <unseal_key>
#
# Audit (stdout -> promtail -> Loki -> Grafana):
#   export VAULT_TOKEN=<root_token>
#   vault audit enable file file_path=stdout
#
# Token do CronJoba snapshotow (vault-snapshot.yaml):
#   kubectl -n davtro02 create secret generic vault-snapshot \
#     --from-literal=VAULT_TOKEN=<root_token>
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-config
  namespace: davtro02
data:
  config-tls.hcl: |
    # KROK 10: API wylacznie po TLS. 8201 pozostaje zarezerwowany przez Vault
    # jako cluster_address (replikacja Raft; pojedynczy node go nie uzywa).
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
      # Klienci autoryzuja sie tokenem/Kubernetes auth, a nie certyfikatem klienta.
      tls_disable_client_certs = true
      tls_min_version   = "tls12"
    }
    telemetry {
      prometheus_retention = "12h"
      # KROK 12 (metryki Vaulta): w tym klastrze jest zwykly Prometheus
      # (Deployment), a nie Prometheus Operator - pliki service-monitors.yaml
      # czekaja na operatora i nikt nie scrape'uje Vaulta. Dlatego job `vault`
      # w prometheus.yaml laczy sie po HTTPS z CA z sekretu `vault-tls`.
      # /v1/sys/metrics normalnie wymaga tokenu, wiec dopuszczamy odczyt
      # BEZ uwierzytelniania: endpoint wystawia wylacznie metryki (liczniki
      # requestow, latencje, stan raft/mounts) - zero sekretow i zero PII.
      unauthenticated_metrics_access = true
      disable_hostname = true
    }
  start.sh: |
    # Secret vault-tls jest niewymaganym? NIE: od KROK 10 jest obowiazkowy.
    # Kubelet utrzymuje kontener w stanie ContainerCreating do chwili utworzenia
    # sekretu przez cert-manager. Po jego pojawieniu Vault startuje tylko na TLS.
    set -eu
    test -s /vault/tls/tls.crt
    test -s /vault/tls/tls.key
    test -s /vault/tls/ca.crt
    echo "Vault: start TLS :8203 (cert z bootstrapowego CA cert-managera)"
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
        runAsUser: 100        # user 'vault' z obrazu hashicorp/vault
        runAsGroup: 1000      # grupa 'vault' z obrazu hashicorp/vault
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      initContainers:
        # microk8s-hostpath nie stosuje fsGroup - katalog PV zostaje root:root
        # (ten sam problem co w postgres.yaml). InitContainer (celowo jako root)
        # nadaje wlasciciela przed startem vault.
        - name: fix-data-permissions
          image: hashicorp/vault:1.17
          command: ["sh", "-c", "chown -R 100:1000 /vault/data"]
          securityContext:
            runAsUser: 0
            runAsGroup: 0
            # celowo root: nadpisuje runAsNonRoot z poziomu poda,
            # inaczej kubelet odrzuca initContainer (jak w postgres.yaml)
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
              # 8201 pozostaje niezmieniony: wewnetrzny channel Raft, nie API.
              value: http://vault-0.vault.davtro02.svc.cluster.local:8201
          readinessProbe:
            # sealedcode=200 + standbyok: pod gotowy tez przed init/unseal
            # (single-node - bez unseala i tak nie obsluzy ruchu)
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
        # vault-tls jest obowiazkowy: bez niego kubelet nie uruchamia kontenera.
        # Dzieki temu nie istnieje moment, w ktorym Vault wystawia API po HTTP.
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
    # 8200 celowo nie istnieje: API jest wylacznie na TLS.
    - { name: raft, port: 8201, targetPort: 8201 }
    - { name: https, port: 8203, targetPort: 8203 }


EOF

cat > ${PROJECT_NAME}/manifests/base/vault-bootstrap.yaml << 'EOF'
# KROK 3.5 (v3): pelna automatyzacja bootstrapu Vaulta - Deployment z petla self-heal (60s).
# Nie zawala syncu ArgoCD (zadnego hooka) i leczy stan po kazdym restarcie/cold-start:
#   1. brak inicjalizacji -> vault operator init (1 key share); unseal_key + root_token
#      na PVC /vault/data (plik bootstrap-keys, 600). Trade-off homelab: w produkcji
#      auto-unseal (cloud KMS / transit).
#   2. sealed -> unseal z pliku
#   3. audit -> stdout (Loki), KV davtro/db (GENERUJE DB_PASSWORD jesli brak) + smtp
#   4. auth kubernetes (+ ClusterRoleBinding system:auth-delegator) + policy/role
#      davtro-apps (ESO) i davtro-snapshot (CronJob backupow)
#   5. database engine + rola davtro-app-rw; jesli haslo davtro w KV nie pasuje do
#      zywego Postgresa -> ALIGN: ALTER USER przez kubectl exec (local trust), czekanie
#      az ESO odswiezy davtro-secrets, rollout restart pgadmin/exporter/spring
# Wymaga: PVC vault-data-vault-0 na tym samym nodzie (RWO, microk8s single-node)
# test.
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
    # KROK 12 (snapshot faktycznie dzialajacy): `vault operator raft snapshot save`
    # od Vault 1.x uzywa sciezki sys/STORAGE/raft/snapshot - nie istniejacej juz
    # w 1.17 sciezki sys/raft/snapshot. Bez tego CronJob konczyl sie bledem:
    #   Error making API request.
    #   URL: .../v1/sys/storage/raft/snapshot   Code: 403 permission denied
    # (GET = "czy trwa juz snapshot" -> read; PUT = zapis/odtworzenie
    #  -> create/update + sudo). Stara sciezka zostaje dla zgodnosci wstecz.
    path "sys/storage/raft/snapshot" { capabilities = ["read", "create", "update", "sudo"] }
    path "sys/raft/snapshot" { capabilities = ["sudo", "read"] }
  # KROK 6 (Transit): szyfrowanie danych aplikacyjnych (DEK/KEK).
  # Aplikacje szyfrują wrażliwe dane (PII, numery telefonów, e-maile) przed zapisem do bazy.
  # Vault zarządza kluczami szyfrującymi (KEK), aplikacje trzymają DEK w pamięci.
  davtro-transit.hcl: |
    path "transit/encrypt/davtro-app" { capabilities = ["update"] }
    path "transit/decrypt/davtro-app" { capabilities = ["update"] }
    path "transit/rewrap/davtro-app" { capabilities = ["update"] }
    path "transit/datakey/davtro-app" { capabilities = ["update"] }
    path "davtro/data/*" { capabilities = ["read"] }
    path "database/creds/davtro-app-rw" { capabilities = ["read"] }
  # KROK 6 (mTLS): certyfikaty klienta dla usług wewnętrznych.
  # Usługi wzajemnie się autoryzują po TLS (mTLS) - wymagany cert client-cert.
  davtro-mtls.hcl: |
    path "pki/issue/davtro-internal" { capabilities = ["create", "update"] }
    path "davtro/data/*" { capabilities = ["read"] }
    path "database/creds/davtro-app-rw" { capabilities = ["read"] }
    path "transit/encrypt/davtro-app" { capabilities = ["update"] }
    path "transit/decrypt/davtro-app" { capabilities = ["update"] }
    path "transit/datakey/davtro-app" { capabilities = ["update"] }
  # KROK 5 (PKI): CA davtro-internal + role certyfikatow.
  # cert-manager (ClusterIssuer/vault-issuer, rola auth: cert-manager)
  # podpisuje przez nie certy ingress + wewnetrzne.
  pki-issuer.hcl: |
    path "pki/sign/davtro-ingress" { capabilities = ["create", "update"] }
    path "pki/issue/davtro-ingress" { capabilities = ["create", "update"] }
    path "pki/sign/davtro-internal" { capabilities = ["create", "update"] }
    path "pki/issue/davtro-internal" { capabilities = ["create", "update"] }
  # KROK 6 (mTLS): policy dla certyfikatow wewnetrznych (davtro-internal).
  # Używane przez vault-issuer-internal do wystawiania certow client-cert.
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
      serviceAccountName: davtro-sa
      # Webhook mutujacy (Kyverno/PSA) wstrzykuje runAsNonRoot:true do poda,
      # a obrazy sa domyslnie root - bez jawnego niezerowego runAsUser kubelet
      # odrzuca kontenery (CreateContainerConfigError / obraz root). Vault i
      # kubectl dzialaja na UID 100 (vault), fsGroup 1000 jak w vault.yaml.
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 1000
        fsGroup: 1000
      initContainers:
        - name: fetch-kubectl
          # bitnami/kubectl:1.30 NIE istnieje na Docker Hub (Bitnami polecialo na ECR) ->
          # ImagePullBackOff przez kilkadziesiat godzin. alpine/k8s jest na Docker Hub
          # i pasuje do serwera microk8s v1.36.
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

              # vault status zwraca exit 2 dla statusu "sealed" (to nie jest blad
              # sieciowy). Petla uzywa exit code jako testu "Vault odpowiada", wiec
              # kod 2 traktujemy jak sukces. Tylko brak odpowiedzi jest bledem.
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
                    log "Vault nie odpowiada przez TLS (ostatni rc=$STATUS_RC): $STATUS"
                    return 1
                  fi
                  sleep 3
                done

                INIT=$(echo "$STATUS" | vfield '"initialized": *[a-z]*')
                SEALED=$(echo "$STATUS" | vfield '"sealed": *[a-z]*')
                [ -n "$INIT" ] || { log "nieparsowalny status Vaulta: $STATUS"; return 1; }

                if [ "$INIT" != "true" ]; then
                  log "brak inicjalizacji -> vault operator init"
                  INIT_JSON=$(vault operator init -key-shares=1 -key-threshold=1 -format=json) || { log "init nieudany - retry"; return 1; }
                  # UWAGA: grep(-o) dziala linia-po-linii, a "unseal_keys_b64" jest tablica
                  # wielolinijkowa (json.MarshalIndent) - wzorzec z "\[[^]]*\]" nigdy
                  # nie lapal klucza. Sed: linia z kluczem -> nastepna linia -> zostaja
                  # tylko znaki base64 (A-Za-z0-9+/=).
                  UKEY=$(printf '%s\n' "$INIT_JSON" | sed -n '/"unseal_keys_b64"/{n;s/[^A-Za-z0-9+\/=]//g;p;q}')
                  RTOKEN=$(echo "$INIT_JSON" | sed -n 's/.*"root_token": *"\([^"]*\)".*/\1/p')
                  if [ -z "$UKEY" ] || [ -z "$RTOKEN" ]; then
                    log "nie udalo sie wyciagnac kluczy z init - retry"
                    return 1
                  fi
                  printf '%s\n%s\n' "$UKEY" "$RTOKEN" > "$KEYS"
                  chmod 600 "$KEYS"
                fi
                [ -f "$KEYS" ] || { log "brak $KEYS (Vault inicjalizowany recznie) - patrz README: Jednorazowa migracja"; return 1; }

                SEALED=$(echo "$STATUS" | vfield '"sealed": *[a-z]*')
                if [ "$SEALED" = "true" ]; then
                  log "unseal"
                  vault operator unseal "$(head -n1 "$KEYS")" >/dev/null
                fi
                export VAULT_TOKEN="$(tail -n1 "$KEYS")"
                if [ -z "$VAULT_TOKEN" ] || ! vault token lookup -format=json >/dev/null 2>&1; then
                  log "root token z $KEYS jest pusty lub nieaktualny - konfiguracja wstrzymana"
                  return 1
                fi
                n=0
                until read_status && [ "$(echo "$STATUS" | vfield '"sealed": *[a-z]*')" = "false" ]; do
                  n=$((n + 1)); [ "$n" -ge 30 ] && { log "vault nadal sealed - retry"; return 1; }
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
                  log "wygenerowano DB_PASSWORD (KV davtro/db)"
                fi
                vault kv get davtro/smtp >/dev/null 2>&1 || vault kv put davtro/smtp SMTP_USER='' SMTP_PASSWORD=''
                # KROK 5b (Auth): haslo admina panelu rezerwacji - GENEROWANE w Vault
                # (KV davtro/auth), nigdy w repo. Jak DB_PASSWORD: gdy klucz istnieje,
                # nie ruszamy go (to jedyna zrodlowa prawdy dla konta 'admin').
                if ! vault kv get davtro/auth >/dev/null 2>&1; then
                  ADMINPASS="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)"
                  [ -n "$ADMINPASS" ] || ADMINPASS="DavtroAdmin$(date +%s)x1"
                  vault kv put davtro/auth ADMIN_PASSWORD="$ADMINPASS"
                  log "wygenerowano ADMIN_PASSWORD (KV davtro/auth)"
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
                  log "database/config odrzucone - ALIGN hasla davtro do wartosci z KV"
                  ALIGN=1
                fi

                if [ "$ALIGN" = "1" ]; then
                  if $KUBECTL -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -tAc \
                      "ALTER USER davtro WITH PASSWORD '$DB_PASSWORD';" >/dev/null 2>&1; then
                    log "haslo davtro w Postgresie zsynchronizowane z KV"
                  else
                    log "ALTER USER nieudany (postgres-db-0 nie gotowy?) - retry w nastepnej petli"
                    return 1
                  fi
                  vault write database/config/davtro-postgresql \
                    plugin_name=postgresql-database-plugin \
                    allowed_roles=davtro-app-rw \
                    connection_url="postgresql://{{username}}:{{password}}@postgres-clusterip.davtro02.svc.cluster.local:5432/davtro_rentals?sslmode=disable" \
                    username=davtro password="$DB_PASSWORD" >/dev/null
                  n=0
                  until [ "$($KUBECTL -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | base64 -d)" = "$DB_PASSWORD" ]; do
                    n=$((n + 1)); [ "$n" -ge 40 ] && break
                    log "czekam az ESO odswiezy davtro-secrets ($n/40)"
                    sleep 15
                  done
                  $KUBECTL -n davtro02 rollout restart deploy/pgadmin deploy/postgres-exporter deploy/spring-app-deployment >/dev/null 2>&1 || true
                  log "restart pgadmin/postgres-exporter/spring (nowe haslo z ESO)"
                fi

                # KROK 5b (Auth): automatyczny ALTER schematu rezerwacji.
                # Kolumny user_id/username sa wymagane przez logowanie rezerwujacych
                # (powiazanie rezerwacji z kontem), a aplikacja laczy sie credsami
                # z Vaulta BEZ praw ALTER - dlatego wykonuje je bootstrap jako
                # wlasciciel bazy. Idempotentne (IF NOT EXISTS) - bezpieczne w petli
                # self-heal i przy pelnym wdrozeniu z ArgoCD od zera.
                if ! $KUBECTL -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -tAc \
                    "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS user_id INT;
                     ALTER TABLE bookings ADD COLUMN IF NOT EXISTS username VARCHAR(100);" >/dev/null 2>&1; then
                  log "ALTER TABLE bookings nieudany (postgres-db-0 nie gotowy?) - retry w nastepnej petli"
                  return 1
                fi
                log "schemat bookings: kolumny user_id/username potwierdzone (automat)"

                # KROK 10: nie ma juz migracji z plain listenera. Secret
                # vault-tls jest montowany jako wymagany, a ConfigMap ma tylko
                # konfiguracje TLS :8203; nie wykonujemy dodatkowego restartu.

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
                # --- KROK 5 (PKI): wewnetrzne CA davtro-internal (self-signed, homelab).
                # W produkcji: root zewnetrzny podpisuje CSR (pki/intermediate/generate
                # -> set-signed), nie self-sign. Idempotentne: za drugim razem tylko
                # odswieza tune/role/policy (root/generate pomijane gdy CA juz istnieje).
                if ! vault secrets list 2>/dev/null | grep -q '^pki/'; then
                  log "PKI: wlaczam silnik pki (intermediate davtro-internal)"
                  vault secrets enable -path=pki pki >/dev/null
                fi
                vault secrets tune -max-lease-ttl=87600h pki >/dev/null 2>&1 || true
                if ! vault read pki/cert/ca >/dev/null 2>&1; then
                  log "PKI: generuje self-signed root CA (homelab)"
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
                # KROK 6 (mTLS): osobny policy + rola auth dla certow wewnetrznych.
                # vault-issuer-internal uzywa tej roli do wystawiania certow client-cert.
                vault policy write pki-internal /sql/pki-internal.hcl >/dev/null
                vault write auth/kubernetes/role/cert-manager-internal \
                  bound_service_account_names="cert-manager,cert-manager-vault" \
                  bound_service_account_namespaces="cert-manager" \
                  policies=pki-internal ttl=1h >/dev/null
                # --- KROK 6 (Transit): silnik szyfrowania danych aplikacyjnych.
                # Aplikacje szyfrują wrażliwe dane (PII, telefony, e-maile) przed zapisem.
                # Vault zarządza KEK (Key Encryption Key), aplikacje trzymają DEK w pamięci.
                if ! vault secrets list 2>/dev/null | grep -q '^transit/'; then
                  log "Transit: wlaczam silnik transit"
                  vault secrets enable transit >/dev/null
                fi
                if ! vault read transit/keys/davtro-app >/dev/null 2>&1; then
                  log "Transit: tworze klucz szyfrujacy davtro-app"
                  vault write -f transit/keys/davtro-app \
                    type=aes256-gcm96 \
                    auto_rotate_period=720h >/dev/null  # auto-rotacja co 30 dni
                fi
                vault policy write davtro-transit /sql/davtro-transit.hcl >/dev/null
                vault write auth/kubernetes/role/davtro-transit \
                  bound_service_account_names=davtro-sa \
                  bound_service_account_namespaces=davtro02 \
                  policies=davtro-transit ttl=1h >/dev/null
                # --- KROK 6 (mTLS): certyfikaty klienta dla usług wewnętrznych.
                # Usługi wzajemnie się autoryzują po TLS (mTLS) - wymagany cert client-cert.
                vault policy write davtro-mtls /sql/davtro-mtls.hcl >/dev/null
                vault write auth/kubernetes/role/davtro-mtls \
                  bound_service_account_names=davtro-sa \
                  bound_service_account_namespaces=davtro02 \
                  policies=davtro-mtls ttl=1h >/dev/null
                log "DONE - Vault skonfigurowany (Transit + mTLS aktywne)"
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
# CronJob: nocny snapshot rafta Vaulta -> PVC vault-backup (retencja 14 dni).
# Token: logowanie do Vaulta przez kubernetes auth (rola davtro-snapshot, policy
# sys/raft/snapshot z sudo) - konfiguruje to Job vault-bootstrap (vault-bootstrap.yaml).
# Ręczne odtworzenie z backupu:
#   vault operator raft snapshot restore /backup/snapshot-XXXX.snap
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vault-backup
  namespace: davtro02
spec:
  accessModes: ["ReadWriteOnce"]
  # storageClassName MUSI byc podane jawnie: microk8s dopisuje je przy
  # tworzeniu wolumenu (bound PVC), a ArgoCD probowalby je zresetowac do null
  # przy kazdym selfHeal -> Kubernetes tego zabrania (spec jest immutable dla
  # bound claims) i CALY sync aplikacji padal (SyncError).
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
  # KROK 12: backup ma byc WYLACZONY - CronJob byl wstrzymany recznie
  # (suspend=true), a w repo tego nie bylo, wiec nikt tego nie widzial.
  # Deklarujemy to jawnie, żeby wyłączenie backupu zostawiało ślad w Git.
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
          # Webhook wstrzykuje runAsNonRoot:true; obraz jest domyslnie root,
          # wiec MUSI byc jawny non-root (uid 100 = vault, gid 1000 + fsGroup =
          # jak w vault.yaml). Bez tego kubelet: CreateContainerConfigError.
          securityContext:
            runAsNonRoot: true
            runAsUser: 100
            runAsGroup: 1000
            fsGroup: 1000
          containers:
            - name: snapshot
              image: hashicorp/vault:1.17
              # Obraz vault domyslnie startuje jako root -> runAsNonRoot z poziomu
              # poda (wstrzykniete tez przez Kyverno) odrzuca kontener. Jawny
              # UID 100 (vault) + GID 1000 jak w vault.yaml / vault-bootstrap.
              securityContext:
                runAsNonRoot: true
                runAsUser: 100
                runAsGroup: 1000
                allowPrivilegeEscalation: false
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
            # UWAGA: mount 'vault-tls' MUSI miec odpowiadajacy wolumen, inaczej
            # CronJob jest niepoprawny i ArgoCD wywala CALY sync (SyncError).
            # optional: cert powstaje dopiero po starcie Vaulta (klero-wajka).
            - name: vault-tls
              secret: { secretName: vault-tls, optional: true }

EOF

cat > ${PROJECT_NAME}/manifests/base/vault-servicemonitor.yaml << 'EOF'
# Wymaga Prometheus Operatora (CRD ServiceMonitor) - analogicznie jak service-monitors.yaml.
# NIE podpiety w kustomization.yaml - odkomentuj tam ta linie po instalacji operatora.
# Zrodlo metryk: /v1/sys/metrics?format=prometheus (telemetry w vault.yaml config.hcl).
# Proponowane alerty w Grafanie/Alertmanagerie:
#   vault_core_sealed == 1                -> Vault zasealowany
#   rate(vault_audit_log_request_error[5m]) > 0 -> bledy auth/autoryzacji
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault
  namespace: davtro02
  labels: { release: prometheus }
spec:
  selector:
    matchLabels:
      app: vault
  endpoints:
    - port: http
      path: /v1/sys/metrics
      params:
        format: ["prometheus"]
      interval: 30s
EOF
truncate -s -1 ${PROJECT_NAME}/manifests/base/vault-servicemonitor.yaml

cat > ${PROJECT_NAME}/manifests/base/vault-server-tls.yaml << 'EOF'
# KROK 9 (Vault HTTPS): certyfikat SERWERA Vaulta NIE MOZE pochodzic z Vault PKI.
#
# Dlaczego: cert-manager podpisuje certyfikat przez Vault PKI (pki/sign/...), czyli
# MUSI najpierw polaczyc sie z dzialajacym Vaultem. A Vault bez wlasnego certyfikatu
# nie wstaje z listenerem TLS (:8203). Bladne kolo ("klero-wajka"):
#   Vault z TLS -> potrzebuje certu -> cert z Vault PKI -> potrzebuje Vaulta.
# Objaw na klastrze: ESO/klienci czekali na secret `vault-tls`, ktory nigdy nie
# powstal, pody nie mogly sie zamontowac, a CALY sync ArgoCD byl Degraded/SyncError.
#
# Rozwiazanie (standardowy wzorzec bootstrapu TLS): male, WEWNETRZNE CA generowane
# przez cert-manager BEZ udzialu Vaulta; cert serwera Vaulta podpisuje to CA.
#   * `vault-tls` istnieje ZANIM Vault wystartuje -> zero blednego kola,
#   * klienci ufaja `ca.crt` z sekretu `vault-tls` (ESO caProvider, transit_client,
#     vault-snapshot) - nic nie trzeba zmieniac po stronie klientow,
#   * CA jest TRWALE (osobny, dlugi TTL) - odnowienie liscia nie zmienia zaufania,
#     wiec rotacja certu nie zrywa polaczen klientow.
# UWAGA: to CA sluzy TYLKO certowi serwera Vaulta. Certy wewnetrznych uslug
# (mTLS fastapi/spring, Ingress) dalej wystawia PKI Vaulta (pki/davtro-internal).
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-selfsigned
  namespace: davtro02
spec:
  selfSigned: {}
---
# Samopodpisana CA (10 lat) - sekret `vault-ca` z tls.crt/tls.key dla Issuer typu CA.
# `rotationPolicy: Never` + dlugi TTL = stabilne zaufanie przez caly czas zycia.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-ca
  namespace: davtro02
spec:
  secretName: vault-ca
  isCA: true
  commonName: davtro-vault-ca
  duration: 87600h    # 10 lat
  renewBefore: 8760h  # 1 rok
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
# Issuer typu CA - podpisuje cert serwera Vaulta (`Certificate vault-tls`).
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-ca
  namespace: davtro02
spec:
  ca:
    secretName: vault-ca
EOF

cat > ${PROJECT_NAME}/manifests/base/pki-issuer.yaml << 'EOF'
# KROK 5 (PKI): cert-manager zamawia certy w Vault PKI, sam odnawia przed
# wygasnieciem (renewBefore) i sklada je w Sekrety tls.crt/tls.key.
# Wymaga na klastrze (raz, poza Gitem): microk8s enable ingress + cert-manager.
# KROK 10: oba Issuery lacza sie z API Vaulta wylacznie po HTTPS :8203.
# CA serwera Vaulta (`davtro-vault-ca`) NIE siedzi w Git - jest pobierana przez
# `spec.vault.caProvider` z Sekretu `vault-tls` (klucz `ca.crt`), ktory tworzy
# cert-manager (SelfSigned -> vault-ca -> vault-tls) w vault-server-tls.yaml.
# UWAGA: adnotacja `cert-manager.io/inject-ca-from-secret` DZIALA TYLKO dla
# issuerow ACME/CA. Dla issuera Vault jedynym wspieranym zrodlem CA jest
# `caProvider` - bez niego `caBundle` jest pusty i cert-manager konczy bledem
# "x509: certificate signed by unknown authority" (brak mozliwosci wystawienia
# certyfikatow, m.in. kafka-server-tls, a w konsekwencji broker nie wstaje).
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
# KROK 6 (mTLS): ClusterIssuer dla certyfikatów wewnętrznych (davtro-internal).
# Używany przez mtls-certificates.yaml do wystawiania certyfikatów client-cert.
# Token auth (jak vault-issuer) - działa niezależnie od Kubernetes auth config.
# HTTPS :8203 + cainjector zapewniają zgodne CA także po czystym namespace.
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer-internal
spec:
  vault:
    server: https://vault.davtro02.svc.cluster.local:8203
    # UWAGA: cert-manager wysyla CSR, wiec endpoint MUSI byc pki/sign (podpisuje
    # CSR). pki/issue ignoruje CSR i generuje WLASNY klucz -> cert-manager
    # odrzuca cert ("public key does not match the CSR", InvalidCertificate).
    path: pki/sign/davtro-internal
    # Bez caProvider cert-manager nie zweryfikuje TLS do Vaulta (brak caBundle
    # w statusie Issuera) - patrz uwaga na górze pliku.
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
# KROK 5 (PKI): certyfikaty ingress (90d, renew 15d przed koncem).
# cert-manager sam renewuje -> Secret tls.crt/tls.key podmieniany bez restartu.
# Po instalacji kontrolera ingress + cert-managera Ingress dostaje HTTPS.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: davtro-tls
  namespace: davtro02
spec:
  secretName: davtro-tls
  duration: 2160h   # 90d
  renewBefore: 360h # 15d
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

cat > ${PROJECT_NAME}/manifests/base/mtls-certificates.yaml << 'EOF'
# KROK 6 (mTLS): certyfikaty klienta dla usług wewnętrznych.
# UWAGA: dla Vault issuer przez endpoint pki/issue/* cert-manager wymaga
# certificateRequestPolicy=SignVerbatim (zachowanie klucza publicznego z CSR).
# Bez tego: "public key does not match the CSR" (InvalidCertificate).
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: fastapi-mtls
  namespace: davtro02
spec:
  secretName: fastapi-mtls
  duration: 720h   # 30d
  renewBefore: 168h # 7d
  commonName: fastapi-web-app.davtro02.svc
  dnsNames:
    - fastapi-web-app.davtro02.svc
    - fastapi-web-app.davtro02.svc.cluster.local
    - fastapi-web-app-svc.davtro02.svc
    - fastapi-web-app-svc.davtro02.svc.cluster.local
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Always
  issuerRef:
    name: vault-issuer-internal
    kind: ClusterIssuer
    group: cert-manager.io
  usages:
    - digital signature
    - key encipherment
    - client auth
    - server auth
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: message-processor-mtls
  namespace: davtro02
spec:
  secretName: message-processor-mtls
  duration: 720h
  renewBefore: 168h
  commonName: message-processor.davtro02.svc
  dnsNames:
    - message-processor.davtro02.svc
    - message-processor.davtro02.svc.cluster.local
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Always
  issuerRef:
    name: vault-issuer-internal
    kind: ClusterIssuer
    group: cert-manager.io
  usages:
    - digital signature
    - key encipherment
    - client auth
    - server auth
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spring-app-mtls
  namespace: davtro02
spec:
  secretName: spring-app-mtls
  duration: 720h
  renewBefore: 168h
  commonName: spring-app.davtro02.svc
  dnsNames:
    - spring-app.davtro02.svc
    - spring-app.davtro02.svc.cluster.local
    - spring-app-svc.davtro02.svc
    - spring-app-svc.davtro02.svc.cluster.local
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Always
  issuerRef:
    name: vault-issuer-internal
    kind: ClusterIssuer
    group: cert-manager.io
  usages:
    - digital signature
    - key encipherment
    - client auth
    - server auth
---
# KROK 9 (Vault HTTPS): certyfikat serwera Vault (TLS na :8203).
# Podpisany przez DEDYKOWANE CA cert-managera (Issuer vault-ca z vault-server-tls.yaml),
# a NIE przez Vault PKI - inaczej powstaloby bledne kolo (cert Vaulta wymagalby
# dzialajacego Vaulta). cert-manager SAM odnawia lisc (renewBefore 7 dni), a zaufanie
# jest stabilne, bo CA ma osobny, dlugi TTL. Sekret vault-tls zawiera tez ca.crt,
# z ktorego korzystaja klienci (ESO caProvider, transit_client, snapshot, helpers).
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
---
# KROK 11: broker Kafka - dwutrybowy start (PLAINTEXT 9092 + mTLS 9094).
# 9093 pozostaje wylacznie dla controllera KRaft.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kafka-server-tls
  namespace: davtro02
spec:
  secretName: kafka-server-tls
  duration: 720h
  renewBefore: 168h
  commonName: kafka-kraft.davtro02.svc
  dnsNames:
    - kafka-kraft
    - kafka-kraft.davtro02
    - kafka-kraft.davtro02.svc
    - kafka-kraft.davtro02.svc.cluster.local
    - kafka-kraft-0.kafka-kraft.davtro02.svc.cluster.local
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Always
  issuerRef:
    name: vault-issuer-internal
    kind: ClusterIssuer
    group: cert-manager.io
  usages:
    - digital signature
    - key encipherment
    - server auth
EOF

cat > ${PROJECT_NAME}/manifests/base/secret-store.yaml << 'EOF'
# External Secrets Operator - polaczenie z Vaultem (Krok 2 planu).
# UWAGA: runbook ponizej jest ZAUTOMATYZOWANY przez Job vault-bootstrap
# (vault-bootstrap.yaml) - na czystym klastrze nie trzeba go recznie wykonywac.
# UWAGA: PRZED podpieciem tego pliku w kustomization.yaml (i pushem do ArgoCD) musi byc:
#
# 1) Vault unsealowany i KV v2 wlaczone (Krok 1):
#      vault secrets enable -path=davtro kv-v2
#
# 2) Sekrety zaladowane (DB_PASSWORD MUSI zgadzac sie z haslem istniejacego Postgresa!):
#      vault kv put davtro/db DB_USER=davtro DB_PASSWORD='<haslo-z-postgresa>'
#      vault kv put davtro/smtp SMTP_USER='' SMTP_PASSWORD=''
#
# 3) Kubernetes auth w Vault + policy + rola + RBAC dla TokenReview:
#      kubectl -n davtro02 create clusterrolebinding vault-tokenreview-binding \
#        --clusterrole=system:auth-delegator --serviceaccount=davtro02:davtro-sa
#      vault auth enable kubernetes
#      vault write auth/kubernetes/config \
#        kubernetes_host="https://kubernetes.default.svc" \
#        kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
#        disable_iss_validation=true
#      vault policy write davtro-apps - <<'EOF'
#      path "davtro/data/*" { capabilities = ["read"] }
#      EOF
#      vault write auth/kubernetes/role/davtro-apps \
#        bound_service_account_names=davtro-sa \
#        bound_service_account_namespaces=davtro02 \
#        policies=davtro-apps ttl=1h
#
# 4) ESO zainstalowany (CRD musza istniec PRZED syncem ArgoCD, inaczej sync padnie):
#      helm repo add external-secrets https://charts.external-secrets.io
#      helm install external-secrets external-secrets/external-secrets \
#        -n external-secrets --create-namespace
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: davtro02
spec:
  provider:
    vault:
      server: "https://vault.davtro02.svc.cluster.local:8203"
      path: "davtro"          # nazwa mounta KV v2 w Vault
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
# Osobny store BEZ path dla database engine (dynamiczne credsy).
# SecretStore z path: davtro dokleja prefix do kazdego klucza
# (szukalby davtro/data/database/creds/... -> "Secret does not exist").
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
truncate -s -1 ${PROJECT_NAME}/manifests/base/secret-store.yaml

cat > ${PROJECT_NAME}/manifests/base/external-secrets.yaml << 'EOF'
# Generuje Secret "davtro-secrets" z Vaulta - ten sam ksztalt kluczy co stary
# secret.yaml, dzieki czemu deploymenty (envFrom: secretRef) zostaja nietkniete.
# Wartosc VAULT_ROOT_TOKEN celowo NIE jest tu przenoszona - root token nie moze
# trafiac do zmiennych srodowiskowych aplikacji (snapshot CronJob ma osobny sekret).
# Rotacja: co refreshInterval ESO pobiera wartosci od nowa z Vault (kv put = aktualizacja).
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
    # KROK 5b (Auth): haslo admina panelu rezerwacji - z Vaulta, nie z repo.
    # Klucz davtro/auth (ADMIN_PASSWORD) GENERUJE bootstrap (vault-bootstrap.yaml,
    # jak DB_PASSWORD), wiec dziala przy pelnym wdrozeniu z ArgoCD bez rak.
    # Rcznie: vault kv put davtro/auth ADMIN_PASSWORD='...silne-haslo...'
    - secretKey: ADMIN_PASSWORD
      remoteRef:
        key: auth
        property: ADMIN_PASSWORD
EOF
truncate -s -1 ${PROJECT_NAME}/manifests/base/external-secrets.yaml

cat > ${PROJECT_NAME}/manifests/base/external-secrets-db-dynamic.yaml << 'EOF'
# KROK 3: dynamiczne credsy PostgreSQL z Vault database engine (VaultDynamicSecret!).
# database/creds/* to NIE KV tylko dynamiczny endpoint -> data/remoteRef daje 403
# ("GET /v1/database/data/creds/..." nie istnieje). VaultDynamicSecret wola
# POST /v1/database/creds/<rola> i sklada username/password w Sekret K8s.
# Wymaga: database engine + rola davtro-app-rw (robi vault-bootstrap).
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
  # Odswiezanie steruje ExternalSecret.refreshInterval (30m) ponizej.
  # Dwa ES moga pozyczac jeden generator (domyslne zachowanie dataFrom).
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
truncate -s -1 ${PROJECT_NAME}/manifests/base/external-secrets-db-dynamic.yaml

cat > ${PROJECT_NAME}/manifests/base/transit-helpers.yaml << 'EOF'
# KROK 6 (Transit): helper scripts dla szyfrowania danych aplikacyjnych.
# Aplikacje używają: transit_encrypt.sh / transit_decrypt.sh
# Vault Agent (lub aplikacja) szyfruje dane przed zapisem do bazy.
# Wymaga: vault-cli w kontenerze aplikacji (albo Vault Agent sidecar).
apiVersion: v1
kind: ConfigMap
metadata:
  name: transit-helpers
  namespace: davtro02
data:
  transit_encrypt: |
    #!/bin/bash
    # Szyfruje dane przez Vault Transit Engine
    # Użycie: echo "dane" | transit_encrypt
    # Zwraca: vault:v1:base64-ciphertext
    
    set -e
    export VAULT_ADDR="https://vault.davtro02.svc.cluster.local:8203"
    export VAULT_CACERT="/etc/vault-tls/ca.crt"
    
    # Pobierz token K8s
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login jwt="$TOKEN" role=davtro-transit 2>/dev/null)
    
    # Szyfruj
    DATA=$(cat)
    PLAINTEXT=$(echo -n "$DATA" | base64 -w0)
    CIPHERTEXT=$(vault write -field=ciphertext transit/encrypt/davtro-app plaintext="$PLAINTEXT" 2>/dev/null)
    
    echo "$CIPHERTEXT"
  
  transit_decrypt: |
    #!/bin/bash
    # Deszyfruje dane z Vault Transit Engine
    # Użycie: echo "vault:v1:..." | transit_decrypt
    # Zwraca: odszyfrowane dane
    
    set -e
    export VAULT_ADDR="https://vault.davtro02.svc.cluster.local:8203"
    export VAULT_CACERT="/etc/vault-tls/ca.crt"
    
    # Pobierz token K8s
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login jwt="$TOKEN" role=davtro-transit 2>/dev/null)
    
    # Deszyfruj
    CIPHERTEXT=$(cat)
    PLAINTEXT=$(vault write -field=plaintext transit/decrypt/davtro-app ciphertext="$CIPHERTEXT" 2>/dev/null)
    echo "$PLAINTEXT" | base64 -d
  
  transit_datakey: |
    #!/bin/bash
    # Generuje Data Encryption Key (DEK) dla lokalnego szyfrowania
    # Użycie: transit_datakey
    # Zwraca: vault:v1:wrapped-key (do przechowania razem z danymi)
    
    set -e
    export VAULT_ADDR="https://vault.davtro02.svc.cluster.local:8203"
    export VAULT_CACERT="/etc/vault-tls/ca.crt"
    
    # Pobierz token K8s
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login jwt="$TOKEN" role=davtro-transit 2>/dev/null)
    
    # Generuj DEK (wrapped)
    KEY=$(vault write -field=wrapped_key transit/datakey/wrapped/davtro-app 2>/dev/null)
    echo "$KEY"
  
  vault_agent_config.hcl: |
    # Vault Agent konfiguracja dla sidecar injection
    # Użycie: vault agent -config=vault_agent_config.hcl
    
    vault {
      address = "https://vault.davtro02.svc.cluster.local:8203"
      tls_skip_verify = false
      retry {
        num_retries = 5
      }
    }
    
    auto_auth {
      method "kubernetes" {
        mount_path = "auth/kubernetes"
        config = {
          role = "davtro-transit"
        }
      }
      sink "file" {
        config = {
          path = "/vault/.vault-token"
        }
      }
    }
    
    template {
      destination = "/etc/transit/credentials"
      contents = <<EOT
    {{ with secret "transit/datakey/davtro-app" }}
    VAULT_TRANSIT_KEY={{ .Data.wrapped_key }}
    {{ end }}
    EOT
    }
---
# KROK 6 (Transit): ExternalSecret dla rotacji Vault token (cert-manager-vault-token alternatywa)
# Używa Vault Agent Auto-Auth do automatycznej rotacji tokena
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
      # KROK 9 (Vault HTTPS): bez caProvider store nie ufa self-signed
      # vault-ca -> 'x509: certificate signed by unknown authority'
      # i SecretStore vault-transit stawal Degraded (blokowal sync ArgoCD).
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

cat > ${PROJECT_NAME}/manifests/base/kafka.yaml << 'EOF'
# Kafka KRaft (bez Zookeepera)
# KROK 11: dual listener — PLAINTEXT :9092 (kompatybilność/testy) oraz mTLS :9094.
# UWAGA: :9093 jest kanałem controllera KRaft i nie może być portem klientów.
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
      # KROK 11 (Kafka SSL) - DLACZEGO initContainer z openssl:
      # obraz apache/kafka:3.7.0 w /etc/kafka/docker/configure (blok "SSL is enabled.")
      # wymaga KEYSTORE/TRUSTSTORE z plikow w /etc/kafka/secrets oraz plikow z haslami:
      #   KAFKA_SSL_KEYSTORE_FILENAME, KAFKA_SSL_KEY_CREDENTIALS, KAFKA_SSL_KEYSTORE_CREDENTIALS,
      #   KAFKA_SSL_TRUSTSTORE_FILENAME, KAFKA_SSL_TRUSTSTORE_CREDENTIALS.
      # Nie zna natomiast zmiennych PEM (KAFKA_SSL_KEYSTORE_*_FILE / *_CERTIFICATES_FILE).
      # Skutek braku KAFKA_SSL_KEYSTORE_FILENAME:
      #   /etc/kafka/docker/configure: line 24: !1: unbound variable  -> exit 1
      #   (funkcja ensure() wola ${!1} przy `set -u`) -> broker w CrashLoopBackOff.
      # Dlatego cert z cert-managera (Secret kafka-server-tls: tls.crt/tls.key/ca.crt)
      # konwertujemy do PKCS12 tym samym wzorcem co scripts/port-forward*.sh
      # (`openssl pkcs12 -export ... -certfile ca.crt`). Hasla sa losowe, generowane
      # przy starcie poda - nie ma ich ani w Git, ani w Secretach klastra.
      initContainers:
        - name: keystores
          image: docker.io/alpine/openssl:3.5.1
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              PEM=/etc/kafka-tls
              OUT=/etc/kafka/secrets
              # 24 znaki base64 bez /+= (bezpieczne w CLI i w plikach hasel obrazu)
              gen() { head -c 32 /dev/urandom | base64 | tr -d '\n/+=' | cut -c1-24; }
              KSP=$(gen); TSP=$(gen)
              printf '%s' "$KSP" > "$OUT/keystore.creds"
              printf '%s' "$KSP" > "$OUT/key.creds"
              printf '%s' "$TSP" > "$OUT/truststore.creds"
              # keystore: lisc + klucz + lancuch CA (klucz i store maja to samo haslo)
              openssl pkcs12 -export \
                -inkey "$PEM/tls.key" -in "$PEM/tls.crt" -certfile "$PEM/ca.crt" \
                -name kafka-server -out "$OUT/kafka.keystore.p12" -passout "pass:$KSP"
              # NIE BUDUJEMY TUTAJ TRUSTSTORE z openssl (`pkcs12 -export -nokeys`).
              # Tak wygenerowany PKCS#12 jest dla JVM "pusty": Java nie traktuje
              # cert-bagu z klucza prywatnego jako trustedCertEntry, wiec PKIX
              # dostaje zero trust anchors. Objaw w logach brokera (KROK 11 byl pozorny):
              #   java.security.InvalidAlgorithmParameterException: the trustAnchors
              #   parameter must be non-empty
              # Przy KAFKA_SSL_CLIENT_AUTH=required broker odrzuca wtedy certy klientow,
              # czyli fastapi/message-processor nie maja jak polaczyc sie z :9094
              # (rdkafka: "Disconnected while requesting ApiVersion").
              # Truststore buduje osobny initContainer `truststore` przez keytool.
              chmod 600 "$OUT"/*
              echo "===> keystore OK: $(ls -1 "$OUT" | tr '\n' ' ')"
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits: { cpu: 100m, memory: 128Mi }
          volumeMounts:
            - { name: kafka-tls, mountPath: /etc/kafka-tls, readOnly: true }
            - { name: kafka-secrets, mountPath: /etc/kafka/secrets }
        # KROK 11 (poprawka): truststore PKCS12 MUSI powstac przez `keytool -importcert`
        # (trustedCertEntry). Java/PKIX odrzuca cert-bag z `openssl pkcs12 -export -nokeys`
        # -> "the trustAnchors parameter must be non-empty" -> przy CLIENT_AUTH=required
        # broker nie przyjmuje zadnego certu klienta.
        # Obraz apache/kafka:3.7.0 ma JDK (/opt/java/openjdk/bin/keytool) i jest juz
        # uzywany przez ten StatefulSet, wiec nie dochodzi zadnego nowego obrazu.
        - name: truststore
          image: apache/kafka:3.7.0
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              KEYTOOL=/opt/java/openjdk/bin/keytool
              OUT=/etc/kafka/secrets
              TSP="$(cat "$OUT/truststore.creds")"
              rm -f "$OUT/kafka.truststore.p12"
              "$KEYTOOL" -importcert -noprompt -trustcacerts \
                -alias davtro-internal-ca \
                -file /etc/kafka-tls/ca.crt \
                -keystore "$OUT/kafka.truststore.p12" \
                -storetype PKCS12 -storepass "$TSP"
              chmod 600 "$OUT/kafka.truststore.p12"
              # Sanity check: truststore musi zawierac dokladnie 1 trustedCertEntry.
              # grep bez trafienia = set -e ubije initContainer (lepiej crash niz
              # broker bez trust anchorow, o czym swiadczy w logach stack trace).
              "$KEYTOOL" -list -v -keystore "$OUT/kafka.truststore.p12" \
                -storepass "$TSP" | grep -E 'Entry type: trustedCertEntry|Alias name: davtro-internal-ca|Your keystore contains'
              echo "===> truststore OK (trustedCertEntry=1)"
          resources:
            requests: { cpu: 10m, memory: 64Mi }
            limits: { cpu: 200m, memory: 256Mi }
          volumeMounts:
            - { name: kafka-tls, mountPath: /etc/kafka-tls, readOnly: true }
            - { name: kafka-secrets, mountPath: /etc/kafka/secrets }
      volumes:
        - name: kafka-tls
          secret:
            secretName: kafka-server-tls
        # PKCS12 + pliki z haslami czytane przez /etc/kafka/docker/configure (emptyDir).
        - name: kafka-secrets
          emptyDir: {}
      containers:
        - name: kafka
          image: apache/kafka:3.7.0
          ports:
            - { name: broker, containerPort: 9092 }
            - { name: controller, containerPort: 9093 }
            - { name: tls, containerPort: 9094 }
          env:
            - { name: CLUSTER_ID, value: "MkU3OEVBNTcwNTJENDM2Qk" }
            - { name: KAFKA_NODE_ID, value: "0" }
            - { name: KAFKA_PROCESS_ROLES, value: "controller,broker" }
            - { name: KAFKA_LISTENERS, value: "PLAINTEXT://:9092,CONTROLLER://:9093,SSL://:9094" }
            - { name: KAFKA_ADVERTISED_LISTENERS, value: "PLAINTEXT://kafka-kraft:9092,SSL://kafka-kraft:9094" }
            - { name: KAFKA_CONTROLLER_QUORUM_VOTERS, value: "0@kafka-kraft-0.kafka-kraft:9093" }
            - { name: KAFKA_CONTROLLER_LISTENER_NAMES, value: "CONTROLLER" }
            - { name: KAFKA_INTER_BROKER_LISTENER_NAME, value: "PLAINTEXT" }
            - { name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP, value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL" }
            # KROK 11 (Kafka SSL): PKCS12 + pliki z haslami z initContainera `keystores`.
            # Nazwy zmiennych MUSZA byc takie, jakich szuka /etc/kafka/docker/configure
            # (obraz sam dokleja /etc/kafka/secrets/ do *FILENAME i czyta hasla z plikow).
            - { name: KAFKA_SSL_KEYSTORE_TYPE, value: "PKCS12" }
            - { name: KAFKA_SSL_KEYSTORE_FILENAME, value: "kafka.keystore.p12" }
            - { name: KAFKA_SSL_KEY_CREDENTIALS, value: "key.creds" }
            - { name: KAFKA_SSL_KEYSTORE_CREDENTIALS, value: "keystore.creds" }
            - { name: KAFKA_SSL_TRUSTSTORE_TYPE, value: "PKCS12" }
            - { name: KAFKA_SSL_TRUSTSTORE_FILENAME, value: "kafka.truststore.p12" }
            - { name: KAFKA_SSL_TRUSTSTORE_CREDENTIALS, value: "truststore.creds" }
            - { name: KAFKA_SSL_CLIENT_AUTH, value: "required" }
            - { name: KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM, value: "https" }
            - { name: KAFKA_LOG_DIRS, value: "/tmp/kraft-combined-logs" }
          resources:
            requests: { cpu: 200m, memory: 512Mi }
            limits: { cpu: 1, memory: 1Gi }
          volumeMounts:
            - { name: kafka-data, mountPath: /tmp/kraft-combined-logs }
            # Keystory PKCS12 + hasla z initContainera (PEM w /etc/kafka-tls czyta tylko initContainer).
            - { name: kafka-secrets, mountPath: /etc/kafka/secrets, readOnly: true }
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
    - { name: tls, port: 9094, targetPort: 9094 }
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
      labels:
        app: kafka-topic-init
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
      serviceAccountName: davtro-sa
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      volumes:
        - { name: db-creds, secret: { secretName: message-processor-db-creds } }
        - { name: transit-helpers, configMap: { name: transit-helpers } }
        # optional: cert vault-tls powstaje po starcie Vaulta (klero-wajka)
        - { name: vault-tls, secret: { secretName: vault-tls, optional: true } }
        - { name: message-processor-mtls, secret: { secretName: message-processor-mtls } }
      containers:
        - name: message-processor
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-consumer:latest
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
          env:
            # Dynamiczne credsy DB z Vaulta (database/creds/davtro-app-rw, rotowane co 30m);
            # db.py przeladowuje silnik SQLAlchemy po wykryciu zmiany plikow.
            - { name: DB_USER_FILE, value: /etc/db-creds/username }
            - { name: DB_PASSWORD_FILE, value: /etc/db-creds/password }
            # KROK 6 (Transit): szyfrowanie danych przez Vault Transit Engine
            - { name: VAULT_TRANSIT_ADDR, value: "https://vault.davtro02.svc.cluster.local:8203" }
            - { name: VAULT_TRANSIT_CA_FILE, value: "/etc/vault-tls/ca.crt" }
            - { name: VAULT_TRANSIT_KEY, value: "davtro-app" }
            - { name: VAULT_TRANSIT_AUTH_ROLE, value: "davtro-transit" }
            - { name: KAFKA_TLS_CERT_FILE, value: "/etc/mtls/tls.crt" }
            - { name: KAFKA_TLS_KEY_FILE, value: "/etc/mtls/tls.key" }
            - { name: KAFKA_CA_FILE, value: "/etc/mtls/ca.crt" }
            # KROK 6 (mTLS): certyfikaty klienta
            - { name: MTLS_CERT_FILE, value: "/etc/mtls/tls.crt" }
            - { name: MTLS_KEY_FILE, value: "/etc/mtls/tls.key" }
            - { name: MTLS_CA_FILE, value: "/etc/mtls/ca.crt" }
          volumeMounts:
            - { name: db-creds, mountPath: /etc/db-creds, readOnly: true }
            - { name: transit-helpers, mountPath: /usr/local/bin/transit, readOnly: true }
            - { name: vault-tls, mountPath: /etc/vault-tls, readOnly: true }
            - { name: message-processor-mtls, mountPath: /etc/mtls, readOnly: true }
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
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      volumes:
        - { name: transit-helpers, configMap: { name: transit-helpers } }
        # optional: cert vault-tls powstaje po starcie Vaulta (klero-wajka)
        - { name: vault-tls, secret: { secretName: vault-tls, optional: true } }
        - { name: spring-app-mtls, secret: { secretName: spring-app-mtls } }
      containers:
        - name: spring-app
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-spring:latest
          ports: [{ containerPort: 8081 }]
          envFrom:
            - secretRef: { name: davtro-secrets }
          env:
            - { name: DB_HOST, value: "postgres-clusterip" }
            - { name: DB_NAME, value: "davtro_rentals" }
            - { name: KAFKA_BOOTSTRAP, value: "kafka-kraft:9094" }
            - { name: KAFKA_TLS_CERT_FILE, value: "/etc/mtls/tls.crt" }
            - { name: KAFKA_TLS_KEY_FILE, value: "/etc/mtls/tls.key" }
            - { name: KAFKA_CA_FILE, value: "/etc/mtls/ca.crt" }
            # KROK 6 (Transit): szyfrowanie danych przez Vault Transit Engine
            - { name: VAULT_TRANSIT_ADDR, value: "https://vault.davtro02.svc.cluster.local:8203" }
            - { name: VAULT_TRANSIT_CA_FILE, value: "/etc/vault-tls/ca.crt" }
            - { name: VAULT_TRANSIT_KEY, value: "davtro-app" }
            - { name: VAULT_TRANSIT_AUTH_ROLE, value: "davtro-transit" }
            # KROK 6 (mTLS): certyfikaty klienta
            - { name: MTLS_CERT_FILE, value: "/etc/mtls/tls.crt" }
            - { name: MTLS_KEY_FILE, value: "/etc/mtls/tls.key" }
            - { name: MTLS_CA_FILE, value: "/etc/mtls/ca.crt" }
          volumeMounts:
            - { name: transit-helpers, mountPath: /usr/local/bin/transit, readOnly: true }
            - { name: vault-tls, mountPath: /etc/vault-tls, readOnly: true }
            - { name: spring-app-mtls, mountPath: /etc/mtls, readOnly: true }
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
      # KROK 12 (Vault metrics): telemetry jest wlaczone w vault.yaml
      # (telemetry { prometheus_retention = "12h" }), ale nikt tych metryk nie
      # scrapowal - service-monitors.yaml czeka na Prometheus Operator, ktorego
      # na tym klastrze nie ma. Stad statyczny job po HTTPS z CA z sekretu
      # `vault-tls` (ten sam plik co uzywa ESO/transit_client).
      # /v1/sys/metrics wymaga tokenu, wiec w vault.yaml wlaczone jest
      # `unauthenticated_metrics_access` - wystawia tylko metryki, zero sekretow.
      - job_name: vault
        scheme: https
        # Vault NIE wystawia metryk pod /metrics - endpoint to /v1/sys/metrics.
        # Bez metrics_path Prometheus dostaje w odpowiedzi "<" (redirect/error UI)
        # i konczy bledem: expected a valid start token ... ("INVALID").
        metrics_path: /v1/sys/metrics
        tls_config:
          ca_file: /etc/prometheus-vault-tls/ca.crt
          server_name: vault.davtro02.svc.cluster.local
        static_configs: [{ targets: ["vault:8203"] }]
  cert-alerts.yml: |
    # KROK 7 (Certy TTL): alerty - bez Alertmanagera widoczne w Prometheus UI (/alerts);
    # gdy dodasz Alertmanagera, rusza tez powiadomienia (Slack/mail).
    groups:
      - name: cert-expiry
        rules:
          - alert: DavtroCertExpiringSoon
            expr: davtro_cert_days_remaining < 14
            for: 1h
            labels: { severity: warning }
            annotations:
              summary: 'Certyfikat {{ $labels.secret }} wygasa za {{ $value }} dni'
              description: 'cert-manager + Vault PKI powinny renewowac automatycznie (renewBefore); sprawdz `kubectl -n davtro02 get certificate`.'
          - alert: DavtroCertExpiringCritical
            expr: davtro_cert_days_remaining < 3
            for: 15m
            labels: { severity: critical }
            annotations:
              summary: 'Certyfikat {{ $labels.secret }} wygasa za {{ $value }} dni (krytycznie)'
              description: 'Renew sie nie wydarzyl na czas - sprawdz cert-manager i Vault PKI (pki/issue davtro-internal / pki/sign).'
          - alert: DavtroCertExpired
            expr: davtro_cert_days_remaining <= 0
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: 'Certyfikat {{ $labels.secret }} WYGASL'
              description: 'Natychmiastowa akcja - TLS przestanie dzialac.'
      - name: target-health
        rules:
          - alert: DavtroTargetDown
            expr: up{job=~"cert-expiry-exporter|fastapi|postgres-exporter|kafka-exporter|node-exporter|vault"} == 0
            for: 5m
            labels: { severity: warning }
            annotations:
              summary: 'Scrape target {{ $labels.job }} nieosiagalny ({{ $labels.instance }})'
              description: 'Prometheus nie widziec targetu od 5 minut - sprawdz pody/usluge.'
  vault-alerts.yml: |
    # KROK 12 (Vault): stany krytyczne sejfu. Bez tych alertow zapieczetowany
    # Vault wygladal po prostu jak "brak metryk" - a do tego czasu nikt nie
    # scrape'owal /v1/sys/metrics w ogole (job `vault` w prometheus.yml).
    # Metryki: vault_status_sealed, vault_raft_peer_is_raft_leader,
    #          vault_mount_status, vault_raft_committed_index/raft_applied_index.
    groups:
      - name: vault-health
        rules:
          - alert: DavtroVaultSealed
            expr: vault_status_sealed == 1
            for: 2m
            labels: { severity: critical }
            annotations:
              summary: 'Vault jest ZAPIEKETOWONY - aplikacje nie dostaną sekretów ani nie odszyfrują PII'
              description: 'Auto-unseal robi `vault-bootstrap` (petla co 60 s). Sprawdz `kubectl -n davtro02 logs deploy/vault-bootstrap -c ensure --tail=50` oraz `vault-0`.'
          - alert: DavtroVaultRaftNoLeader
            expr: max(vault_raft_peer_is_raft_leader) < 1
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: 'Brak ledera Raft - zapis do Vaulta wstrzymany'
              description: 'Sprawdz logi `vault-0` (utrata dysku/quorum, restart).'
          - alert: DavtroVaultRaftLag
            expr: (max(vault_raft_committed_index) - max(vault_raft_applied_index)) > 1000
            for: 10m
            labels: { severity: warning }
            annotations:
              summary: 'Raft: committed-applied > 1000 (opoznienie zapisu)'
              description: 'Zwykle dysk/PVC pod `vault-data-vault-0` jest wolny albo walczy o IO.'
          - alert: DavtroVaultMountNotMounted
            expr: vault_mount_status{status!="mounted"} == 1
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: 'Mount {{ $labels.path }} nie jest zamontowany (status={{ $labels.status }})'
              description: 'Sprawdz `vault secrets list` oraz logi `vault-0` - brak silnika blokuje sekrety/Transit/PKI.'
          - alert: DavtroVaultTransitStale
            expr: time() - vault_transit_last_rotation_time > 86400 * 35
            for: 1h
            labels: { severity: warning }
            annotations:
              summary: 'Klucz Transit nie był rotowany > 35 dni (auto_rotate_period=30 dni)'
              description: 'Sprawdz `vault read transit/keys/davtro-app` - po rotacji warto przepuścić wiersze przez `transit/rewrap`.'
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
            # KROK 12: CA bootstrapowego CA Vaulta (dla scrape https://vault:8203).
            # Ten sam sekret montuja fastapi/ESO/transit_client - jeden plik CA.
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
# KROK 8 (Alertmanager): powiadomienia z alertow Prometheus (cert-expiry + targety).
# Config alertmanager.yml jest TEMPLATEM - SMTP_USER/SMTP_PASSWORD (z Vaulta przez
# ESO, Secret davtro-secrets) podstawia start.sh przy starcie poda. Zero sekretow
# w ConfigMapie i w repo.
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
    # Podstawia sekrety SMTP do template'u i startuje Alertmanager.
    # Bez SMTP_HOST (SMTP nie skonfigurowany) pisze na blackhole 127.0.0.1:25 -
    # alerty widoczne w UI Alertmanagera, dostarczenie email dopiero po sekretach.
    set -eu
    HOST="${SMTP_HOST:-127.0.0.1}"
    PORT="${SMTP_PORT:-25}"
    USER="${SMTP_USER:-x}"
    PASS="${SMTP_PASSWORD:-x}"
    FROM="${FROM_EMAIL:-admin@davtro.local}"
    TO="${ALERT_EMAIL_TO:-$FROM}"
    [ -n "${SMTP_HOST:-}" ] || echo "UWAGA: brak SMTP_HOST - alerty nie wysylaja email (widoczne w UI :9093)"
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
          # Sekrety SMTP z Vaulta (ESO -> davtro-secrets) + SMTP_HOST/PORT z configmapy FastAPI
          envFrom:
            - secretRef: { name: davtro-secrets }
            - configMapRef: { name: fastapi-config }
          env:
            # Odbiorca alertow (ustawione na zyczenie uzytkownika)
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
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
      containers:
        - name: postgres-exporter
          image: prometheuscommunity/postgres-exporter:v0.15.0
          env:
            # Credsy z sekretu generowanego przez ESO (external-secrets.yaml) - zero
            # hasel w Git. HOST poprawiony: postgres-clusterip (Service); wczesniej
            # wskazywal nieistniejacy 'postgres-db' i exporter nie mial polaczenia.
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
# KROK 7 (Certy TTL): eksporter dat wygasniecia certyfikatow.
# Skanuje Secrety typu kubernetes.io/tls w namespace davtro02 (davtro-tls,
# spark-tls, *-mtls) i wystawia metryki dla Prometheusa:
#   davtro_cert_not_after_seconds{secret=...}  - unix ts wygasniecia
#   davtro_cert_days_remaining{secret=...}     - dni do wygasniecia
# Reguly alertow (cert-alerts w prometheus.yaml) ostrzegaja 14/7 dni przed TTL.
# Certyfikaty i tak renewuje cert-manager + Vault PKI - to warstwa widocznosci.
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
    # KROK 7: eksporter wygasania certyfikatow (stdlib only, bez zaleznosci).
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
        # ssl._ssl._test_decode_cert - stdlib parser X.509 (bez bibliotek zewnetrznych)
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
            - name: data
              mountPath: /loki
            - name: config
              mountPath: /etc/loki
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

cat > ${PROJECT_NAME}/manifests/base/network-policies.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: davtro02
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-namespace
  namespace: davtro02
spec:
  podSelector: {}
  ingress:
    - from: [{ podSelector: {} }]
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-eso-to-vault
  namespace: davtro02
spec:
  podSelector:
    matchLabels:
      app: vault
  ingress:
    - from:
        # Caly ns external-secrets (pody ESO) -> naprawia
        # 'context deadline exceeded' w SecretStore vault-backend.
        # UWAGA: sam namespaceSelector (bez podSelector) - kombinacja
        # podSelector+namespaceSelector w JEDNYM elemencie from to AND
        # (ten sam pod musialby byc w obu ns), wiec musi byc osobno.
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: external-secrets
      ports:
        # KROK 10: ESO komunikuje sie z Vaultem wylacznie po TLS.
        - { protocol: TCP, port: 8203 }
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-web
  namespace: davtro02
spec:
  podSelector: { matchLabels: { app: fastapi-web-app } }
  ingress:
    - from: []
      ports: [{ protocol: TCP, port: 8080 }]
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-frontend
  namespace: davtro02
spec:
  podSelector: { matchLabels: { app: frontend } }
  ingress:
    - from: []
      ports: [{ protocol: TCP, port: 8080 }]
  policyTypes: [Ingress]
---
# KROK 5 (PKI): kontroler ingress (ns ingress, po `microk8s enable ingress`)
# musi dobic do backendow po HTTP (terminacja TLS na kontrolerze).
# Bez tej reguly default-deny odcina ruch kontroler -> fastapi/frontend.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller-to-web
  namespace: davtro02
spec:
  podSelector:
    matchLabels:
      app: fastapi-web-app
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress
      ports:
        - { protocol: TCP, port: 8080 }
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller-to-frontend
  namespace: davtro02
spec:
  podSelector:
    matchLabels:
      app: frontend
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress
      ports:
        - { protocol: TCP, port: 8080 }
  policyTypes: [Ingress]
---
# KROK 5/10 (PKI): kontroler cert-manager (ns cert-manager) musi dobic
# do API Vaulta po HTTPS :8203 (ClusterIssuer sklada CSR przez pki/sign/*).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-certmanager-to-vault
  namespace: davtro02
spec:
  podSelector:
    matchLabels:
      app: vault
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: cert-manager
      ports:
        - { protocol: TCP, port: 8203 }
  policyTypes: [Ingress]
EOF

cat > ${PROJECT_NAME}/manifests/base/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-ingress
  namespace: davtro02
  annotations:
    argocd.argoproj.io/ignore-healthcheck: "true"
spec:
  ingressClassName: public
  # KROK 5 (PKI): terminacja TLS certem z cert-managera (Secret davtro-tls,
  # Certificate/davtro-tls <- ClusterIssuer/vault-issuer <- Vault PKI).
  # Bez kontrolera ingress + cert-managera pole czeka (Ingress bez adresu).
  tls:
    - hosts: [davtro.local]
      secretName: davtro-tls
  rules:
    - host: davtro.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service: { name: fastapi-web-app-svc, port: { number: 80 } }
          - path: /
            pathType: Prefix
            backend:
              service: { name: frontend-svc, port: { number: 80 } }
          - path: /grafana
            pathType: Prefix
            backend:
              service: { name: grafana, port: { number: 3000 } }
          - path: /kafka-ui
            pathType: Prefix
            backend:
              service: { name: kafka-ui, port: { number: 80 } }
          - path: /pgadmin
            pathType: Prefix
            backend:
              service: { name: pgadmin, port: { number: 80 } }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spark-ingress
  namespace: davtro02
  annotations:
    argocd.argoproj.io/ignore-healthcheck: "true"
spec:
  ingressClassName: public
  # KROK 5 (PKI): jak wyzej (Secret spark-tls <- Certificate/spark-tls).
  tls:
    - hosts: [spark.davtro.local]
      secretName: spark-tls
  rules:
    - host: spark.davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: spark-master-svc, port: { number: 8082 } }
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
    - name: require-ghcr-images
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Obrazy kontenerow w namespace 'davtro' musza pochodzic z ghcr.io lub zaufanych rejestrow."
        pattern:
          spec:
            containers:
              - image: "ghcr.io/* | bitnami/* | postgres/* | redis/* | grafana/* | prom/* | hashicorp/* | dpage/* | provectuslabs/* | danielqsj/* | eclipse-temurin/* | python:*"
    - name: require-resource-requests-limits
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
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
              namespaces: [davtro]
      validate:
        message: "Kontenery uprzywilejowane sa niedozwolone."
        pattern:
          spec:
            =(securityContext):
              =(privileged): "false"
EOF

cat > ${PROJECT_NAME}/manifests/base/service-monitors.yaml << 'EOF'
# Wymaga Prometheus Operatora (CRD ServiceMonitor)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: davtro-services
  namespace: davtro02
  labels: { release: prometheus }
spec:
  selector:
    matchExpressions:
      - { key: app, operator: In, values: [fastapi-web-app, postgres-exporter, kafka-exporter] }
  endpoints:
    - port: metrics
      interval: 15s
EOF

cat > ${PROJECT_NAME}/manifests/base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# KROK 5 (PKI): Vault CA + cert-manager. AKTYWNE - cert-manager zainstalowany
# na klastrze (CRD ClusterIssuer/Certificate istnieja, SA cert-manager-vault +
# Secret cert-manager-vault-token gotowe). Kolejnosc celowa: issuer przed certami.
resources:
- namespace.yaml
- serviceaccount.yaml
- configmap.yaml
- secret-store.yaml
- external-secrets.yaml
- external-secrets-db-dynamic.yaml
- deployment.yaml
- service.yaml
- frontend.yaml
- hpa.yaml
- pdb.yaml
- postgres.yaml
- redis.yaml
- vault.yaml
- vault-snapshot.yaml
- vault-bootstrap.yaml
- kafka.yaml
- message-processor.yaml
- spring-app.yaml
- spark.yaml
- prometheus.yaml
- cert-expiry-exporter.yaml
- alertmanager.yaml
- exporters.yaml
- grafana.yaml
- loki.yaml
- promtail.yaml
- tempo.yaml
- pgadmin.yaml
- kafka-ui.yaml
- network-policies.yaml
- ingress.yaml
- kyverno-policy.yaml
- pki-issuer.yaml
- vault-server-tls.yaml
- certificates.yaml
- mtls-certificates.yaml
- transit-helpers.yaml

images:
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
  newTag: 6093746ec4a15ca3da98588ce20d991d4e07907b
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-consumer
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-consumer
  newTag: 6093746ec4a15ca3da98588ce20d991d4e07907b
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-frontend
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-frontend
  newTag: 6093746ec4a15ca3da98588ce20d991d4e07907b
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-spark
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-spark
  newTag: 6093746ec4a15ca3da98588ce20d991d4e07907b
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-spring
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-spring
  newTag: 6093746ec4a15ca3da98588ce20d991d4e07907b
EOF

# ============================================
# KUSTOMIZE OVERLAYS
# ============================================

cat > ${PROJECT_NAME}/manifests/overlays/production/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: davtro02

resources:
  - ../../base

images:
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-consumer
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-spring
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-frontend
    newTag: latest

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

images:
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
    newTag: staging
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-consumer
    newTag: staging
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-spring
    newTag: staging
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02-frontend
    newTag: staging

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
    repoURL: https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02.git
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
      # UWAGA: celowo BEZ Replace=true. Tryb Replace podmienia cala definicje
      # obiektu, a Kubernetes zabrania updatu immutable fields istniejacych
      # zasobow (bound PersistentVolumeClaims, spec StatefulSetow poza
      # dozwolonymi polami) -> kazdy taki dryf zawalal CALY sync aplikacji
      # (SyncError, retry x5). Bez Replace ArgoCD aktualizuje w miejscu to,
      # co sie da, a reszta (vid. storageClassName w vault-snapshot.yaml)
      # jest utrzymywana zgodnie w manifestach.
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

provider "github" {
  token = var.github_token
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "ghcr_pat" {
  type      = string
  sensitive = true
}

resource "github_repository" "repo" {
  name        = "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02"
  description = "Davtro Apartments - platforma wynajmu krotkoterminowego (K8s/ArgoCD/Kafka/Redis/Vault)"
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
name: CI/CD - Davtro Platform

permissions:
  contents: write
  packages: write

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_BASE: ghcr.io/${{ github.repository_owner }}/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
  KUSTOMIZE_PATH: ./manifests/overlays/production

jobs:
  build-fastapi:
    # Pomin build dla commitow bota CI - inaczej kazdy bot-commit
    # uruchamia nowy build i kolejny bot-commit = nieskonczona petla.
    # Autor commita (nie actor - bo push idzie PAT-em usera).
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT_02 }}
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
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT_02 }}
      - uses: docker/build-push-action@v6
        with:
          context: ./frontend
          file: ./frontend/Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_BASE }}-frontend:latest
            ${{ env.IMAGE_BASE }}-frontend:${{ github.sha }}
      # UWAGA: widocznosc pakietu GHCR NIE da sie zmienic przez REST API
      # (POST .../change-visibility -> 404). Pierwszy raz pakiet trzeba
      # ustawic jako PUBLIC recznie w UI GitHuba (Package settings ->
      # Danger Zone -> Change visibility). Potem widocznosc zostaje.

  build-consumer:
    if: github.event.head_commit.author.username != 'github-actions[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT_02 }}
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
        with:
          distribution: temurin
          java-version: '17'
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT_02 }}
      - name: Build Spring Boot application
        run: mvn -f java-app/pom.xml clean package -DskipTests
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
        with:
          distribution: temurin
          java-version: '17'
      - uses: sbt/setup-sbt@v1
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GHCR_PAT_02 }}
      - name: Build Spark assembly
        working-directory: ./spark-jobs
        run: sbt -batch clean assembly
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
        with:
          token: ${{ secrets.GHCR_PAT_02 }}
      - name: Set new image tags via Kustomize
        run: |
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
      - name: Commit updated manifests
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add manifests/base/kustomization.yaml
          git diff --cached --quiet || git commit -m "ci: aktualizacja obrazow na ${{ github.sha }}"
          git push
EOF

# ============================================
# KYVERNO POLICIES (standalone)
# ============================================

cat > ${PROJECT_NAME}/kyverno-policies/kyverno-policy.yaml << 'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: davtro-baseline-policy-standalone
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-resource-requests-limits
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [davtro]
      validate:
        message: "Kazdy kontener musi miec requests/limits."
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
              namespaces: [davtro]
      validate:
        message: "Privileged niedozwolone."
        pattern:
          spec:
            =(securityContext):
              =(privileged): "false"
EOF

# ============================================
# DOCS
# ============================================

cat > ${PROJECT_NAME}/README.md << 'EOF'
# Davtro Apartments – platforma wynajmu krótkoterminowego (Full Open Source)

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02`
Namespace docelowy: `davtro`
KUSTOMIZE_IMAGE_ID: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02`
KUSTOMIZE_PATH: `./manifests/production`

## Architektura przepływu rezerwacji
1. Użytkownik rezerwuje termin na stronie (kalendarz w `app/templates/index.html`).
2. `FastAPI` (`app/main.py`) zapisuje rezerwację w PostgreSQL, buforuje event w Redis, publikuje do Kafka (`booking-events`).
3. `message-processor` (`app/consumer.py`) konsumuje event, wysyła e-mail (potwierdzenie + faktura proforma) i aktualizuje status w PostgreSQL.
4. Zgody marketingowe trafiają do tematu `marketing-events`, konsumowane tak samo, dodatkowo agregowane przez `spark-jobs/marketing_analytics.py`.
5. `spring-app-deployment` udostępnia panel raportowy/administracyjny na tych samych danych.
6. Sekrety pochodzą z HashiCorp Vault przez External Secrets Operator (ESO) – `secret-store.yaml` + `external-secrets.yaml`; bootstrap Vaulta (init/unseal/KV/auth/database) robi automatycznie Job `vault-bootstrap` (PostSync). Aplikacje Python dostają dynamiczne credsy DB z `database/creds/davtro-app-rw` (rotacja co 30 min).

## Struktura repo
```
app/                  # FastAPI (web + API rezerwacji) + konsument Kafka + wysyłka e-mail
java-app/             # Spring Boot – panel raportowy
spark-jobs/           # Spark – analityka marketingowa
manifests/base/       # Wszystkie zasoby K8s (Kustomize base)
manifests/production/ # Overlay produkcyjny (namespace davtro, replicas)
kyverno-policies/     # Polityki Kyverno (kopiowane też do manifests/base)
.github/workflows/    # CI: build obrazów -> GHCR -> aktualizacja Kustomize -> ArgoCD sync
argocd/application.yaml
terraform/            # Terraform Cloud (workspace github-actions-terraform)
```

## Uruchomienie lokalnie (dev, bez K8s)
```bash
cd app/.. 
python -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## Wdrożenie na MicroK8s przez ArgoCD
1. Włącz ingress: `microk8s enable ingress`
2. Utwórz sekrety realne (nie commituj!) lub skonfiguruj Vault + ArgoCD Vault Plugin.
3. Zastosuj `argocd/application.yaml`: `kubectl apply -f argocd/application.yaml -n argocd`
4. Push do `main` -> GitHub Actions zbuduje obrazy i zaktualizuje tagi w `manifests/base/kustomization.yaml` -> ArgoCD (auto-sync) wdroży zmiany.

## WAŻNE – rzeczy do dopracowania przed produkcją
- ~~sekrety w repo~~ ZROBIONE: Vault (raft na PVC) + ESO generują `davtro-secrets`; Job `vault-bootstrap` automatyzuje init/unseal/KV/auth/database po każdym syncu.
- ~~Vault dev-mode~~ ZROBIONE: storage raft na PVC. Do produkcji HA: Helm chart z auto-unseal (cloud KMS / transit) zamiast klucza unseal na PVC.
- `service-monitors.yaml` wymaga Prometheus Operatora (CRD `ServiceMonitor`) – jest wyłączony w `kustomization.yaml`, odkomentuj po instalacji operatora.
- SMTP nie jest skonfigurowany – bez zmiennych `SMTP_*` e-maile tylko logują się do stdout (`app/email_sender.py`).
- Obrazy produkcyjne CI/CD budują się pod `ghcr.io/<twoja-organizacja>/...` – ustaw `github.repository_owner` zgodnie z Twoim kontem/organizacją.



# Davtro Apartments – platforma wynajmu krotkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02`
Namespace: `davtro`

## Architektura
1. **Frontend** (SPA) → Nginx
2. **FastAPI** → PostgreSQL + Redis (cache) + Kafka (producent)
3. **message-processor** (consumer) → Kafka → email + PostgreSQL update
4. **Spring Boot** → panel raportowy / admin
5. **Spark** → analityka marketingowa z Kafka
6. **Vault** → sekrety (raft + ESO + auto-bootstrap; dynamiczne credsy DB dla FastAPI/consumer)
7. **Observability** → Prometheus + Grafana + Loki + Tempo

## Lokalne uruchomienie (dev)
```bash
cd backend-fastapi
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## K8s / ArgoCD
```bash
kubectl apply -f argocd/application.yaml -n argocd
```
Push do `main` → GitHub Actions buduje obrazy → Kustomize aktualizuje tagi → ArgoCD sync.

### Dostep ArgoCD do prywatnego repozytorium GitHub

ArgoCD musi miec osobne dane dostepowe do prywatnego repozytorium. Tokenu nie
wpisuj do tego repozytorium ani do `application.yaml`. Utworz secret w
namespace `argocd` z tokenem GitHub (PAT powinien miec co najmniej `Contents:
Read`):

```bash
read -s GITHUB_PAT
export GITHUB_PAT
kubectl create secret generic davtro-github-repo \
	-n argocd \
	--from-literal=type=git \
	--from-literal=url=https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02.git \
	--from-literal=username=exea-centrum \
	--from-literal=password="$GITHUB_PAT" \
	--dry-run=client -o yaml |
	kubectl label -f - argocd.argoproj.io/secret-type=repository --local -o yaml |
	kubectl apply -f -
unset GITHUB_PAT
```

Nastepnie odswiez ArgoCD:

```bash
kubectl annotate application davtro-website -n argocd \
	argocd.argoproj.io/refresh=hard --overwrite
kubectl get application davtro-website -n argocd -w
```

## WAZNE – przed produkcja
- ~~Vault dev-mode~~ ZROBIONE (raft + auto-bootstrap); produkcja HA: Helm chart + auto-unseal
- ~~ArgoCD Vault Plugin (AVP)~~ ZROBIONE inaczej: External Secrets Operator (ESO)
- Skonfiguruj realny SMTP w secretach
- Zainstaluj Prometheus Operator jesli chcesz uzyc ServiceMonitor

# Vault: pełna automatyzacja (full-auto cold start)

Usunięcie projektu + wklejenie `argocd/application.yaml` do ArgoCD wystarcza – bez kroków ręcznych:

1. ArgoCD deployuje stack; Job `vault-bootstrap` (PostSync, idempotentny) inicjalizuje i unsealuje Vault (klucze: `/vault/data/bootstrap-keys` na PVC `vault-data-vault-0`), generuje `DB_PASSWORD` do KV `davtro/db`, włącza audit→stdout (Loki), auth kubernetes (+ `system:auth-delegator`), policy/role `davtro-apps`, database engine + rolę `davtro-app-rw` (retry aż Postgres wstanie) oraz `davtro-snapshot`.
2. ESO tworzy `davtro-secrets` (statyczne KV: db/smtp) → Postgres robi initdb z tym hasłem → ESO tworzy dynamiczne credsy `fastapi-db-creds` / `message-processor-db-creds` z `database/creds/davtro-app-rw` (rotacja co 30 min; aplikacje przełączają pool(e) w locie – `watch_db_creds` / `get_engine()`).
3. CronJob `vault-snapshot` robi nocny snapshot rafta (logowanie po ServiceAccount, retencja 14 dni).

## Jednorazowa migracja klastra sprzed automatyzacji

Jeżeli Vault był inicjalizowany ręcznie (przed wdrożeniem `vault-bootstrap.yaml`), Job wyexituje z prośbą o plik kluczy. Skonsumuj raz wartości z pierwotnego `vault operator init`:

```bash
kubectl -n davtro02 exec vault-0 -- sh -c \
  'printf "%s\n%s\n" "<UNSEAL_KEY>" "<ROOT_TOKEN>" > /vault/data/bootstrap-keys && chmod 600 /vault/data/bootstrap-keys'
kubectl -n davtro02 delete job vault-bootstrap
kubectl -n argocd annotate application davtro-website argocd.argoproj.io/refresh=hard --overwrite
kubectl -n davtro02 logs -f job/vault-bootstrap   # czekaj na "[bootstrap] DONE"
```

## Weryfikacja Vault + ESO

```bash
kubectl -n davtro02 get externalsecret                                            # 3x SYNCED=True
kubectl -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -c '\du'  # userzy v-token-...
kubectl -n davtro02 logs deploy/fastapi-web-app | grep -i "przelaczono\|creds"
```

Roadmapa: **Krok 4** = PKI (cert-manager + Vault issuer dla ingress TLS) + GitHub OIDC dla CI; opcjonalnie Transit (szyfrowanie PII w PostgreSQL) i migracja Springa na Spring Cloud Vault.

---

# Platforma Davtro — co to za strona i po co każdy komponent (wersja bez sekretów)

> Ta sekcja nie zawiera żadnych haseł, tokenów ani certyfikatów. Opisuje wyłącznie przeznaczenie elementów systemu.

## 1. Jaka to strona i do czego służy

**Davtro Apartments** to platforma wynajmu krótkoterminowego (apartamenty / pokoje na doby):

- gość wybiera apartament i termin w kalendarzu na stronie,
- wysyła rezerwację przez API,
- system zapisuje rezerwację, wysyła e-mail z potwierdzeniem i fakturą proforma,
- zgody marketingowe gościa zasilają analitykę marketingową,
- panel administracyjno-raportowy służy obsłudze obiektu.

Wejście od internetu: host `davtro.local` (Ingress `davtro-ingress`):

| Ścieżka | Dokąd prowadzi | Do czego służy |
|---|---|---|
| `/` | `frontend-svc:80` (Nginx) | strona dla gościa: oferta, kalendarz, formularz rezerwacji |
| `/api` | `fastapi-web-app-svc:80` | REST API rezerwacji (tworzenie / odczyt / status) |
| `/grafana` | `grafana:3000` | podgląd metryk, logów i tracingu |
| `/kafka-ui` | `kafka-ui:80` | podgląd topiców i wiadomości Kafka (diagnostyka) |
| `/pgadmin` | `pgadmin:80` | przegląd bazy przez przeglądarkę (administracja) |
| `spark.davtro.local /` | `spark-master-svc:8082` | podgląd jobów Spark (analityka) |

## 2. Mapa komponentów — co do czego uderza i po co istnieje

```text
gość (przeglądarka)
  |
  v
Ingress davtro.local
  |-- / ---------> frontend (Nginx, statyczna strona + kalendarz)
  |-- /api ------> fastapi-web-app (API rezerwacji)
  |                   |-- zapis/odczyt ---> postgres (baza rezerwacji)
  |                   |-- cache/sesje ----> redis (szybka pamięć)
  |                   |-- event rezerwacji -> kafka-kraft (kolejka zdarzeń)
  |-- /grafana ---> grafana (metryki + logi + trace w jednym miejscu)
  |-- /kafka-ui --> kafka-ui (podgląd kolejek)
  |-- /pgadmin ---> pgadmin (podgląd bazy)
```

```text
kafka-kraft (bookings-created, email-invoices, marketing-actions)
  |
  +--> message-processor (konsument: wysyła e-maile, aktualizuje status w DB)
  +--> spring-app (panel raportowy Java na tych samych danych)
  +--> spark-master + spark-worker x2 (analityka marketingowa w tle)

postgres-exporter / kafka-exporter / node-exporter
  |
  v
prometheus (metryki) ---> grafana (wykresy)

promtail (zbiera logi z każdego noda)
  |
  v
loki (magazyn logów) ---> grafana (przeszukiwanie logów)

aplikacje (OpenTelemetry)
  |
  v
tempo (magazyn trace) ---> grafana (podgląd ścieżki requestu)

vault + vault-bootstrap (sejf na sekrety, auto-konfiguracja po starcie)
  |
  v
external-secrets (SecretStore + ExternalSecret + VaultDynamicSecret)
  |
  v
Sekrety Kubernetes (davtro-secrets, fastapi-db-creds, message-processor-db-creds)
  |
  v
postgres / fastapi / message-processor / spring-app / pgadmin / postgres-exporter
```

## 3. Warstwa aplikacji — opis każdego elementu

### frontend (Nginx)
- **Co to:** statyczna strona dla gościa (oferta, zdjęcia, kalendarz, formularz).
- **Po co:** szybkie serwowanie treści bez obciążania API.
- **Z kim gada:** przeglądarka gościa; formularz woła `/api` na backendzie.

### fastapi-web-app — API (Python FastAPI, 3 repliki na produkcji)
- **Co to:** główne API rezerwacji (`POST /api/...`, `GET /api/health` do sond).
- **Po co:** przyjmuje rezerwacje, waliduje terminy, zapisuje do bazy, odkłada event na kolejkę.
- **Z kim gada:** `postgres-clusterip:5432` (zapis rezerwacji), `redis:6379` (cache dostępności / idempotencja), `kafka-kraft:9092` (publikacja eventu). Konfiguracja z `ConfigMap fastapi-config`, sekrety z `davtro-secrets` + dynamiczne credsy z `/etc/db-creds`.
- **Odporność:** `HPA 2-8 (CPU 70%)`, `PDB minAvailable: 1`, sondy `readiness/liveness /api/health`.

### message-processor (Python consumer)
- **Co to:** pracownik w tle, konsument Kafki.
- **Po co:** odbiera event rezerwacji, wysyła e-mail (potwierdzenie + faktura proforma) i przestawia status rezerwacji w bazie; konsumuje też zgody marketingowe. Bez niego rezerwacja zostałaby w statusie "oczekująca".
- **Z kim gada:** `kafka-kraft:9092` (konsumpcja), `postgres-clusterip:5432` (update statusu), SMTP (wysyłka).

### spring-app-deployment (Java Spring Boot `:8081`)
- **Co to:** panel raportowo-administracyjny na tych samych danych co FastAPI.
- **Po co:** zestawienia, raporty, obsługa obiektu w technologii Java.
- **Z kim gada:** `postgres-clusterip`, `kafka-kraft`.

### spark-master + spark-worker x2 (Apache Spark 3.5)
- **Co to:** silnik obliczeń batch (master `:7077`, UI `:8082` + 2 workery).
- **Po co:** analityka marketingowa (`spark-jobs/marketing_analytics.py`), np. agregacje zgód / kampanii. Odciąża bazę transakcyjną od ciężkich zapytań.
- **Z kim gada:** workerzy łączą się do `spark://spark-master-svc:7077`.

## 4. Warstwa danych — po co Postgres, Redis i Kafka

### postgres-db (PostgreSQL 16, StatefulSet 1x + headless Service `postgres-clusterip:5432`)
- **Co to:** jedyne trwałe źródło prawdy (baza `davtro_rentals`).
- **Po co:** rezerwacje, statusy, użytkownicy, zgody marketingowe.
- **Trwałość:** wolumen `pgdata 5Gi` (szablon PVC w StatefulSecie).
- **Dostęp:** tylko wewnątrz klastra; graficznie przez `pgadmin`, metryki przez `postgres-exporter`.

### redis (Redis 7, Deployment 1x, `redis:6379`)
- **Co to:** pamięć podręczna klucz-wartość (in-memory).
- **Po co:** cache dostępności terminów, sesje, bufor eventów, odciążenie Postgresa od powtarzalnych odczytów. Dane ulotne — po restarcie odtwarzane z bazy.
- **Z kim gada:** wyłącznie `fastapi-web-app` (zmienne `REDIS_HOST/REDIS_PORT` z ConfigMap).

### kafka-kraft (Apache Kafka 3.7, KRaft bez Zookepera, StatefulSet 1x)
- **Co to:** rozproszony dziennik zdarzeń (kolejka): broker `:9092` + kontroler `:9093`, wolumen `kafka-data 5Gi`.
- **Po co:** rozprzęga API od wysyłki maili i analityki. API odpowiada gościowi od razu, a ciężka praca (mail, faktura, agregacje) dzieje się asynchronicznie. Topici (po 3 partycje): `bookings-created` (nowe rezerwacje), `email-invoices` (maile/faktury), `marketing-actions` (zgody/akcje marketingowe).
- **Kto tworzy topici:** `Job kafka-topic-job` (ArgoCD `PostSync` hook, samousuwalny po 300 s).
- **Kto produkuje / konsumuje:** producent `fastapi-web-app`; konsumenci `message-processor`, `spring-app`, joby Spark.
- **Podgląd:** `kafka-ui`.

## 5. Bezpieczeństwo i sekrety — po co Vault i External Secrets (bez wartości)

### vault (HashiCorp Vault 1.17, StatefulSet 1x, `:8200/:8201`, storage Raft na PVC)
- **Co to:** sejf na sekrety z szyfrowaniem danych w spoczynku.
- **Po co:** żadne hasło nie leży w Git. Aplikacje dostają je dopiero w klastrze.
- **Tryb:** Raft na wolumenie `vault-data 2Gi`, UI włączone, telemetria dla Prometheusa.

### vault-bootstrap (Deployment z pętlą self-heal co 60 s)
- **Co to:** automatyczny konfigurator sejfu po starcie od zera (cold start).
- **Po co:** odtwarza cały łańcuch bez klikania: init/unseal, audit do stdout, wpisy KV, auth Kubernetes, polityki i role, silnik bazy danych + wyrównanie hasła z żywym Postgresem. Kończy logiem `DONE - Vault skonfigurowany`.

### vault-snapshot (CronJob `0 3 * * *` + PVC `vault-backup 2Gi`)
- **Co to:** nocna kopia Rafta (`snapshot-STAMP.snap`, retencja 14 dni).
- **Po co:** odtworzenie sejfu po awarii (`raft snapshot restore`).
- **Uwierzytelnianie:** tokenem krótkoterminowym z logowania JWT ServiceAccount (rola snapshotowa), bez stałych sekretów w YAML.

### SecretStore `vault-backend` / `vault-dynamic` + ExternalSecret + VaultDynamicSecret
- **Co to:** most `Vault -> Kubernetes Secrets` (operator ESO w osobnym namespace `external-secrets`).
- **Po co:** zamienia wpisy sejfu na natywne Sekrety K8s, które Deploymenty montują jako env/pliki:
  - `davtro-secrets` (statyczne: login/hasło DB + SMTP),
  - `fastapi-db-creds` / `message-processor-db-creds` (dynamiczne, rotowane konta DB z silnika `database/creds/...`).
- **Rotacja:** statyczne co 1 h, dynamiczne co 30 min; aplikacje Python przeładowują pule połączeń w locie.

## 6. Obserwowalność — po co Prometheus, Grafana, Loki, Promtail i Tempo

### prometheus (`prometheus:9090`)
- **Co to:** baza metryk liczbowych (scrape co 15 s).
- **Po co:** odpowiada na pytania "ile requestów?", "jaki czas odpowiedzi?", "czy baza/Kafka żyją?".
- **Skąd zbiera:** `fastapi-web-app-svc:80`, `postgres-exporter:9187`, `kafka-exporter:9308`, `node-exporter:9100`.

### postgres-exporter / kafka-exporter / node-exporter
- **Co to:** tłumacze stanu na metryki dla Prometheusa.
- **Po co:** osobno widać kondycję bazy, kolejek i samego węzła (CPU/RAM/dysk/sieć).

### grafana (`grafana:3000`, gotowy dashboard `Davtro Platform Overview`)
- **Co to:** jedno okno na metryki + logi + trace (źródła: Prometheus, Loki, Tempo).
- **Po co:** diagnoza "co się stało?" bez grzebania po podach. Wystawiona pod `/grafana`.

### loki (`loki:3100`) + promtail (DaemonSet na każdym nodzie)
- **Co to:** magazyn logów (Loki) + zbieracz logów (Promtail czyta `/var/log/containers/*.log` i wysyła do Loki).
- **Po co:** przeszukiwanie logów wszystkich podów (API, konsument, Vault audit ze stdout) z jednego miejsca w Grafanie.

### tempo (`tempo:3200`)
- **Co to:** magazyn trace rozproszonych (OpenTelemetry, protokoły OTLP http+grpc).
- **Po co:** pokazuje ścieżkę jednego requestu przez system (frontend -> API -> DB/Kafka -> konsument), więc widać, który krok spowalnia rezerwację.

### kafka-ui (`:8080`, ścieżka `/kafka-ui`) i pgadmin (`:80`, ścieżka `/pgadmin`)
- **Po co:** szybki podgląd "czy eventy płyną?" (Kafka) i "co leży w bazie?" (Postgres) bez wchodzenia na pody.

## 7. Wejście, skalowanie, odporność i polityki

- **Ingress:** `davtro-ingress` (klasa `public`, host `davtro.local`) + `spark-ingress` (`spark.davtro.local`). Bez zainstalowanego kontrolera Ingress obiekty istnieją, ale nie dostają adresu — stan oczekiwany w tym środowisku (adnotacja `ignore-healthcheck`).
- **Skalowanie:** `HPA fastapi-web-app-hpa` (2-8 replik przy CPU 70%), na produkcji bazowo 3 repliki API, 2 repliki frontendu i 2 workery Spark.
- **Dostępność:** `PDB fastapi-web-app-pdb` (min. 1 dostępny przy pracach na węzłach).
- **Sieć:** `NetworkPolicy default-deny-ingress` (domyślnie zamknij) + jawne otwarcia: ruch wewnątrz namespacu, ESO (`external-secrets`) do Vaulta (`:8200/:8201`), wejście do API i frontendu.
- **Ład:** `ClusterPolicy davtro-baseline-policy` (Kyverno, `Enforce`): obrazy z zaufanych rejestrów, wymagane `requests/limits`, zakaz kontenerów uprzywilejowanych. `ServiceMonitor`y są przygotowane, ale nieaktywne do czasu instalacji Prometheus Operatora.

## 8. GitOps w jednym zdaniu

`push do main -> CI buduje 5 obrazów GHCR (api, consumer, frontend, spark, spring) i podbija tagi w Kustomize -> ArgoCD (Aplikacja davtro-website, auto-sync prune+selfHeal, CreateNamespace) buduje overlay production i odtwarza cały powyższy graf w namespace davtro02`.

```text
                    +---------------- GitHub HEAD ------------------+
                    | manifests/overlays/production -> ../../base   |
                    +---------------+--------------------------------+
                                    | pull + kustomize build
                          +---------v-----------+
                          | ArgoCD davtro-website (ns argocd) |
                          +---------+-----------+
                                    | apply -> ns davtro02
        +---------------------------+-----------------------------+
        |                           |                             |
+-------v-------+        +----------v----------+       +----------v----------+
|   VAULT LAYER |        |     DATA LAYER      |       |     APP LAYER       |
| vault-0 :8200 |<-------+ postgres-db :5432   |<------+ fastapi-web-app :8080|
| bootstrap     |  dynamic| redis :6379         |  SQL  | message-processor  |
| snapshot 03:00|  creds  | kafka-kraft :9092   |  KV   | spring-app :8081   |
+-------+-------+        +----------+----------+       | frontend nginx :8080 |
        ^                           ^                  | spark master/worker |
        | K8s auth                    |                  +----------+----------+
        | jwt davtro-sa               |                             | Kafka topics
+-------v---------------------------v-----------------------------v----------+
| SECRETS LAYER: SecretStore vault-backend/vault-dynamic + ExternalSecret     |
| davtro-secrets + VaultDynamicSecret db-creds-davtro-app-rw ->               |
| fastapi-db-creds / message-processor-db-creds                               |
+--------------------------------+--------------------------------------------+
                                 |
        +------------------------v-------------------------------------------+
        | OBSERVABILITY: prometheus:9090 <- postgres/kafka/node-exporter      |
        | grafana:3000 (Prometheus+Loki+Tempo) | loki:3100 <- promtail (DS)   |
        | tempo:3200 | kafka-ui:8080 | pgadmin:80                             |
        +------------------------------------------------+-------------------+
                                         |
                          +--------------v---------------+
                          | EDGE: Ingress davtro.local   |
                          | /api->fastapi /->frontend    |
                          | /grafana /kafka-ui /pgadmin  |
                          | spark.davtro.local->spark-ui |
                          +------------+-----------------+
                                       |
                    +--------+---------+---------+--------+
                    | HPA fastapi 2-8 CPU70% | PDB minAvailable:1 |
                    | NetworkPolicy deny+allow | Kyverno Enforce |
                    +--------------------------------------------+
```

## 9. Szczegółowy opis architektury i przepływu

### 9.1 Diagram przepływu (Full Stack)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    GITHUB (main branch)                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ CI/CD Pipeline (.github/workflows/ci-cd.yaml)                                   │   │
│  │  1. Build 5 obrazów Docker (api, consumer, frontend, spring, spark) -> GHCR     │   │
│  │  2. kustomize edit set image -> tagi w manifests/base/kustomization.yaml        │   │
│  │  3. git commit + git push                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
                                          │
                                          │ webhook / auto-sync (3min)
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    ARGOCD (namespace: argocd)                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ Application: davtro-website                                                      │   │
│  │  source: manifests/overlays/production -> ../../base                            │   │
│  │  destination: https://kubernetes.default.svc, namespace: davtro02               │   │
│  │  syncPolicy: automated (prune: true, selfHeal: true)                           │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
                                          │
                                          │ kustomize build + apply
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              MICROK8S CLUSTER (namespace: davtro02)                     │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              EDGE LAYER (Ingress + TLS)                         │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ Ingress Controller (nginx, microk8s enable ingress)                     │  │   │
│  │  │  TLS termination: cert-manager + Vault PKI                             │  │   │
│  │  │  Hosts: davtro.local, spark.davtro.local                                │  │   │
│  │  │  Secrets: davtro-tls, spark-tls (auto-rotowane przez cert-manager)     │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │         │                    │                    │                    │          │
│  │    /api -> fastapi      / -> frontend      /grafana -> grafana   /spark -> spark │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              APPLICATION LAYER                                  │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ fastapi-web-app  │  │ message-processor│  │ spring-app       │              │   │
│  │  │ (Python/FastAPI) │  │ (Kafka consumer) │  │ (Java/Spring)    │              │   │
│  │  │ :8080, replicas:3│  │ :8080, replicas:1│  │ :8081, replicas:1│              │   │
│  │  │ HPA: 2-8, CPU70% │  │                  │  │                  │              │   │
│  │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘              │   │
│  │           │ Kafka produce        │ Kafka consume        │                        │   │
│  │           ▼                      ▼                      ▼                        │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ frontend (nginx) │  │ spark-master     │  │ spark-worker (x2)│              │   │
│  │  │ :8080, replicas:2│  │ :8082, :4040     │  │ :8083             │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.2 Data Layer

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              DATA LAYER                                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ postgres-db      │  │ redis            │  │ kafka-kraft      │              │   │
│  │  │ (StatefulSet)    │  │ (Deployment)     │  │ (StatefulSet)    │              │   │
│  │  │ :5432            │  │ :6379            │  │ :9092            │              │   │
│  │  │ PVC: 5Gi         │  │ cache layer      │  │ topics:          │              │   │
│  │                                               └──────────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.3 Secrets Layer (Vault + ESO)

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              SECRETS LAYER (Vault + ESO)                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ vault-0 (StatefulSet, raft storage na PVC 2Gi)                           │  │   │
│  │  │  :8200 (API)                                                             │  │   │
│  │  │  Engines:                                                                │  │   │
│  │  │   - kv-v2: davtro/db, davtro/smtp (sekrety aplikacji)                   │  │   │
│  │  │   - database: postgres-clusterip (dynamiczne credsy)                    │  │   │
│  │  │   - pki: davtro-internal CA (certyfikaty TLS)                            │  │   │
│  │  │  Auth: kubernetes (SA davtro-sa), token (cert-manager)                   │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │           ▲                                       ▲                              │   │
│  │           │ K8s auth (jwt)                        │ token auth                   │   │
│  │           │                                       │                              │   │
│  │  ┌────────┴───────────────────────────────────────┴─────────────────────────┐  │   │
│  │  │ vault-bootstrap (Deployment, self-heal co 60s)                           │  │   │
│  │  │  1. vault operator init (1 key share) -> bootstrap-keys na PVC           │  │   │
│  │  │  2. vault operator unseal (auto-unseal z pliku)                         │  │   │
│  │  │  3. kv-v2: davtro/db, davtro/smtp (generuje DB_PASSWORD jeśli brak)     │  │   │
│  │  │  4. audit: stdout -> promtail -> Loki -> Grafana                         │  │   │
│  │  │  5. auth/kubernetes/config + role davtro-apps, davtro-snapshot           │  │   │
│  │  │  6. database engine + role davtro-app-rw (TTL 1h/24h)                    │  │   │
│  │  │  7. PKI: root CA + roles davtro-ingress, davtro-internal                 │  │   │
│  │  │  8. Policy pki-issuer + role cert-manager (token auth)                  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ External Secrets Operator (namespace: external-secrets)                  │  │   │
│  │  │  SecretStore vault-backend: kv-v2, K8s auth, role davtro-apps           │  │   │
│  │  │  SecretStore vault-dynamic: database engine (bez path prefix)           │  │   │
│  │  │                                                                          │  │   │
│  │  │  ExternalSecret davtro-secrets -> Secret davtro-secrets (refresh: 1h)    │  │   │
│  │  │   DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                        │  │   │
│  │  │                                                                          │  │   │
│  │  │  VaultDynamicSecret db-creds-davtro-app-rw                              │  │   │
│  │  │   -> ExternalSecret fastapi-db-creds (refresh: 30m)                      │  │   │
│  │  │   -> ExternalSecret message-processor-db-creds (refresh: 30m)            │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ cert-manager (namespace: cert-manager)                                   │  │   │
│  │  │  ClusterIssuer vault-issuer:                                             │  │   │
│  │  │   server: http://vault.davtro02.svc.cluster.local:8200                   │  │   │
│  │  │   path: pki/sign/davtro-ingress                                          │  │   │
│  │  │   auth: tokenSecretRef cert-manager-vault-token                          │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate davtro-tls:                                                 │  │   │
│  │  │   Secret: davtro-tls, CN=davtro.local, duration: 90d, renew: 15d        │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate spark-tls:                                                  │  │   │
│  │  │   Secret: spark-tls, CN=spark.davtro.local, duration: 90d, renew: 15d   │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```
### 9.3 Secrets Layer (Vault + ESO)

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              SECRETS LAYER (Vault + ESO)                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ vault-0 (StatefulSet, raft storage na PVC 2Gi)                           │  │   │
│  │  │  :8200 (API)                                                             │  │   │
│  │  │  Engines:                                                                │  │   │
│  │  │   - kv-v2: davtro/db, davtro/smtp (sekrety aplikacji)                   │  │   │
│  │  │   - database: postgres-clusterip (dynamiczne credsy)                    │  │   │
│  │  │   - pki: davtro-internal CA (certyfikaty TLS)                            │  │   │
│  │  │  Auth: kubernetes (SA davtro-sa), token (cert-manager)                   │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │           ▲                                       ▲                              │   │
│  │           │ K8s auth (jwt)                        │ token auth                   │   │
│  │           │                                       │                              │   │
│  │  ┌────────┴───────────────────────────────────────┴─────────────────────────┐  │   │
│  │  │ vault-bootstrap (Deployment, self-heal co 60s)                           │  │   │
│  │  │  1. vault operator init (1 key share) -> bootstrap-keys na PVC           │  │   │
│  │  │  2. vault operator unseal (auto-unseal z pliku)                         │  │   │
│  │  │  3. kv-v2: davtro/db, davtro/smtp (generuje DB_PASSWORD jeśli brak)     │  │   │
│  │  │  4. audit: stdout -> promtail -> Loki -> Grafana                         │  │   │
│  │  │  5. auth/kubernetes/config + role davtro-apps, davtro-snapshot           │  │   │
│  │  │  6. database engine + role davtro-app-rw (TTL 1h/24h)                    │  │   │
│  │  │  7. PKI: root CA + roles davtro-ingress, davtro-internal                 │  │   │
│  │  │  8. Policy pki-issuer + role cert-manager (token auth)                  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ External Secrets Operator (namespace: external-secrets)                  │  │   │
│  │  │  SecretStore vault-backend: kv-v2, K8s auth, role davtro-apps           │  │   │
│  │  │  SecretStore vault-dynamic: database engine (bez path prefix)           │  │   │
│  │  │                                                                          │  │   │
│  │  │  ExternalSecret davtro-secrets -> Secret davtro-secrets (refresh: 1h)    │  │   │
│  │  │   DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                        │  │   │
│  │  │                                                                          │  │   │
│  │  │  VaultDynamicSecret db-creds-davtro-app-rw                              │  │   │
│  │  │   -> ExternalSecret fastapi-db-creds (refresh: 30m)                      │  │   │
│  │  │   -> ExternalSecret message-processor-db-creds (refresh: 30m)            │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ cert-manager (namespace: cert-manager)                                   │  │   │
│  │  │  ClusterIssuer vault-issuer:                                             │  │   │
│  │  │   server: http://vault.davtro02.svc.cluster.local:8200                   │  │   │
│  │  │   path: pki/sign/davtro-ingress                                          │  │   │
│  │  │   auth: tokenSecretRef cert-manager-vault-token                          │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate davtro-tls:                                                 │  │   │
│  │  │   Secret: davtro-tls, CN=davtro.local, duration: 90d, renew: 15d        │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate spark-tls:                                                  │  │   │
│  │  │   Secret: spark-tls, CN=spark.davtro.local, duration: 90d, renew: 15d   │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.4 Observability Layer + Network Policies + Backup

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              OBSERVABILITY LAYER                                 │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ prometheus       │  │ grafana          │  │ loki             │              │   │
│  │  │ :9090            │  │ :3000            │  │ :3100            │              │   │
│  │  │ metrics scrape   │  │ dashboards       │  │ log aggregation  │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ tempo            │  │ promtail         │  │ kafka-ui         │              │   │
│  │  │ :3200            │  │ (DaemonSet)      │  │ :8080            │              │   │
│  │  │ trace storage    │  │ log collection   │  │ Kafka management │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  │  ┌──────────────────┐  ┌──────────────────┐                                    │   │
│  │  │ pgadmin          │  │ exporters        │                                    │   │
│  │  │ :80              │  │ postgres, kafka, │                                    │   │
│  │  │ DB management    │  │ node             │                                    │   │
│  │  └──────────────────┘  └──────────────────┘                                    │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              NETWORK POLICIES                                    │   │
│  │  default-deny-ingress (zamyka wszystko)                                          │   │
│  │  allow-intra-namespace (ruch wewnątrz davtro02)                                  │   │
│  │  allow-eso-to-vault (external-secrets -> vault:8200)                             │   │
│  │  allow-certmanager-to-vault (cert-manager -> vault:8200)                         │   │
│  │  allow-ingress-controller-to-web (ingress -> fastapi/frontend:8080)              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              BACKUP LAYER                                        │   │
│  │  vault-snapshot (CronJob, 03:00 daily) -> PVC vault-backup (retencja 14 dni)     │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 9.5 Odpowiedzialność komponentów

| Komponent | Plik(y) | Odpowiedzialność |
|-----------|---------|------------------|
| **ArgoCD** | `argocd/application.yaml` | GitOps: synchronizuje stan klastra z repozytorium. Auto-sync co 3 minuty, self-heal (naprawia ręczne zmiany), prune (usuwa zasoby nie w Git). |
| **GitHub Actions** | `.github/workflows/ci-cd.yaml` | CI: buduje 5 obrazów Docker (api, consumer, frontend, spring, spark) i push do GHCR. Aktualizuje tagi w `manifests/base/kustomization.yaml`. |
| **Kustomize** | `manifests/base/kustomization.yaml` | Deklaracja wszystkich zasobów K8s. Overlay production nadpisuje namespace, replica count, image tags. |
| **Vault** | `vault.yaml`, `vault-bootstrap.yaml` | Centralne zarządzanie sekretami: KV v2 (sekrety aplikacji), database engine (dynamiczne credsy), PKI (certyfikaty TLS), autoryzacja (K8s + token). |
| **vault-bootstrap** | `vault-bootstrap.yaml` | Automatyczna inicjalizacja Vault: init, unseal, konfiguracja KV/auth/database/PKI. Self-heal co 60s. |
| **External Secrets Operator** | `secret-store.yaml`, `external-secrets.yaml`, `external-secrets-db-dynamic.yaml` | Most między Vault a Kubernetes: synchronizuje sekrety z Vault do K8s Secrets. |
| **cert-manager** | `pki-issuer.yaml`, `certificates.yaml` | Zarządzanie certyfikatami TLS: zamawia z Vault PKI, automatycznie odnawia przed wygaśnięciem. |
| **Ingress Controller** | `ingress.yaml`, `network-policies.yaml` | Reverse proxy: terminacja TLS, routing do usług (fastapi, frontend, grafana, spark). |
| **Kyverno** | `kyverno-policy.yaml` | Polityki bezpieczeństwa: wymagane requests/limits, zakaz kontenerów uprzywilejowanych, zaufane rejestry. |

### 9.6 Przepływ sekretów (Vault -> Aplikacja)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT (namespace: davtro02)                                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ KV v2 Engine (mount: davtro)                                        │   │
│  │  davtro/db: { DB_USER: davtro, DB_PASSWORD: *** }                  │   │
│  │  davtro/smtp: { SMTP_USER: ***, SMTP_PASSWORD: *** }               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ K8s auth (SA davtro-sa, role davtro-apps)   │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ExternalSecret davtro-secrets (refresh: 1h)                         │   │
│  │  -> Secret davtro-secrets (namespace: davtro02)                     │   │
│  │     DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ envFrom: secretRef                          │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Aplikacje: fastapi, message-processor, spring-app                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT (namespace: davtro02)                                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Database Engine (mount: database)                                   │   │
│  │  Role: davtro-app-rw                                                │   │
│  │    creation: CREATE ROLE ... LOGIN PASSWORD ... VALID UNTIL ...     │   │
│  │    revocation: DROP ROLE ...                                        │   │
│  │    default_ttl: 1h, max_ttl: 24h                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ K8s auth (SA davtro-sa, role davtro-apps)   │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ VaultDynamicSecret db-creds-davtro-app-rw                           │   │
│  │  -> POST /v1/database/creds/davtro-app-rw                          │   │
│  │  -> generuje: { username: v-token-davtro-app-rw-xxx, password: *** }│   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ ExternalSecret (refresh: 30m)              │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Secrets: fastapi-db-creds, message-processor-db-creds               │   │
│  │  zawartość: { username: ..., password: ... }                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ volumeMount: /etc/db-creds (read-only)     │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Aplikacje:                                                          │   │
│  │  fastapi: DB_USER_FILE=/etc/db-creds/username                       │   │
│  │           DB_PASSWORD_FILE=/etc/db-creds/password                   │   │
│  │           (main.py watch_db_creds: przeladowuje pool przy zmianie)  │   │
│  │  message-processor: DB_USER_FILE, DB_PASSWORD_FILE                  │   │
│  │                      (db.py: przeladowuje SQLAlchemy)               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.7 Przepływ certyfikatów (Vault PKI -> Ingress)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT PKI (namespace: davtro02)                                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ PKI Engine (mount: pki)                                             │   │
│  │  Root CA: davtro-internal (self-signed, homelab)                    │   │
│  │   CN=davtro-internal CA, TTL=87600h (10 lat)                        │   │
│  │                                                                     │   │
│  │  Roles:                                                             │   │
│  │   davtro-ingress:                                                   │   │
│  │     allowed_domains: davtro.local, spark.davtro.local               │   │
│  │     allow_subdomains: true, max_ttl: 2160h (90d)                    │   │
│  │   davtro-internal:                                                  │   │
│  │     allowed_domains: svc.cluster.local, cluster.local               │   │
│  │     allow_any_name: true, enforce_hostnames: false                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ token auth (cert-manager-vault-token)       │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ClusterIssuer vault-issuer (cert-manager)                           │   │
│  │  server: http://vault.davtro02.svc.cluster.local:8200               │   │
│  │  path: pki/sign/davtro-ingress                                      │   │
│  │  auth: tokenSecretRef cert-manager-vault-token                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Certificate resources                        │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Certificate davtro-tls                                              │   │
│  │  Secret: davtro-tls, CN=davtro.local                                │   │
│  │  duration: 2160h (90d), renewBefore: 360h (15d)                     │   │
│  │                                                                     │   │
│  │ Certificate spark-tls                                               │   │
│  │  Secret: spark-tls, CN=spark.davtro.local                           │   │
│  │  duration: 2160h (90d), renewBefore: 360h (15d)                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ cert-manager generuje Secret z tls.crt/tls.key
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Secrets: davtro-tls, spark-tls (type: kubernetes.io/tls)            │   │
│  │  zawartość: { tls.crt: <cert PEM>, tls.key: <key PEM> }             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Ingress spec.tls.secretName                  │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Ingress Controller (nginx)                                          │   │
│  │  TLS termination na poziomie Ingress                                │   │
│  │  Hosts: davtro.local, spark.davtro.local                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.8 Co jest potrzebne poza projektem (wymagania zewnętrzne)

| Komponent | Instalacja | Status w projekcie |
|-----------|------------|-------------------|
| **MicroK8s** | `snap install microk8s --classic` | Wymagany jako runtime |
| **Ingress Controller** | `microk8s enable ingress` | CRD + Deployment w namespace `ingress` |
| **cert-manager** | `helm install jetstack/cert-manager --set crds.enabled=true` | CRD ClusterIssuer/Certificate wymagane przed syncem |
| **External Secrets Operator** | `helm install external-secrets external-secrets/external-secrets -n external-secrets` | CRD ExternalSecret/SecretStore wymagane przed syncem |
| **Kyverno** | `helm install kyverno kyverno/kyverno -n kyverno` | CRD ClusterPolicy wymagane przed syncem |
| **GitHub Container Registry** | Public package visibility | Obrazy Docker: `ghcr.io/<org>/...` |
| **DNS** | Wpisy A/CNAME dla `davtro.local`, `spark.davtro.local` | Wymagane dla dostępu z zewnątrz |


### 9.9 Czy działa full automatic deployment?

**TAK** — po jednorazowej instalacji komponentów zewnętrznych, cały pipeline działa automatycznie:

```
1. Developer push do main branch
2. GitHub Actions buduje 5 obrazów Docker -> GHCR
3. GitHub Actions aktualizuje tagi w kustomization.yaml -> git push
4. ArgoCD wykrywa zmiany (co 3 min) -> kustomize build -> apply
5. Pody są rolling update z nowymi obrazami
6. cert-manager monitoruje Certificate resources -> odnawia TLS przed wygaśnięciem
7. ESO synchronizuje sekrety z Vault co 1h (static) / 30min (dynamic)
8. vault-bootstrap self-heal co 60s (naprawia stan Vault po restarcie)
9. vault-snapshot CronJob codziennie o 03:00 -> backup raft na PVC
```


### 9.10 Czy można wstawić zewnętrzne certyfikaty?

**TAK** — 3 opcje:

**Opcja A: Import do Vault PKI (zalecane)**
```bash
# Wygeneruj CSR przez cert-manager, podpisz zewnętrznym CA, importuj do Vault
vault write pki/intermediate/set-signed certificate=@intermediate.cert.pem
# Vault PKI przejmuje zarządzanie rotacją
```

**Opcja B: Ręczny Secret (bez cert-manager)**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: davtro-tls
  namespace: davtro02
type: kubernetes.io/tls
data:
  tls.crt: <base64 encoded cert>
  tls.key: <base64 encoded key>
```
Następnie zmień `ingress.yaml` aby używał tego Secrets. **Uwaga**: brak auto-rotacji — trzeba ręcznie aktualizować.

**Opcja C: cert-manager + Let's Encrypt (dla publicznych domen)**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@davtro.local
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: public
```


### 9.11 Rotacja certyfikatów, tokenów i kluczy

| Zasób | Mechanizm rotacji | Lokalizacja | Częstotliwość |
|-------|-------------------|-------------|---------------|
| **Certyfikaty TLS** (davtro-tls, spark-tls) | cert-manager odnawia automatycznie `renewBefore: 360h (15d)` przed expiry | Secret: `davtro-tls`, `spark-tls` (ns davtro02) | Co 90 dni (auto) |
| **Certyfikaty mTLS** (fastapi-mtls, message-processor-mtls, spring-app-mtls) | cert-manager odnawia automatycznie `renewBefore: 168h (7d)` przed expiry | Secret: `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` (ns davtro02) | Co 30 dni (auto) |
| **Vault PKI Root CA** | Brak auto-rotacji (10 lat TTL). Rotacja ręczna: nowy CA + re-sign wszystkich certów | Vault PKI engine | Ręcznie (rocznie) |
| **Vault PKI Root CA** | Brak auto-rotacji (10 lat TTL). Rotacja ręczna: nowy CA + re-sign wszystkich certów | Vault PKI engine | Ręcznie (rocznie) |
| **Dynamiczne credsy DB** | Vault database engine generuje nowe przy każdym request. Stare TTL 1h -> automatycznie wygasa | Secret: `fastapi-db-creds`, `message-processor-db-creds` (ns davtro02) | Co 30 min (ESO refresh) |
| **KV sekrety** (davtro/db, davtro/smtp) | ESO synchronizuje z Vault. Ręczna zmiana w Vault -> ESO podłapie | Secret: `davtro-secrets` (ns davtro02) | Co 1h (ESO refresh) |
| **cert-manager-vault-token** | Ręczna: `vault token create` -> update Secret | Secret: `cert-manager-vault-token` (ns cert-manager) | Ręcznie (rocznie) |
| **Vault unseal key** | Na PVC `/vault/data/bootstrap-keys` (tryb 1-of-1, homelab). Produkcja: auto-unseal (cloud KMS) | PVC: vault-data-vault-0 | Ręcznie (po każdym restarcie) |
| **Vault snapshot** | CronJob codziennie 03:00, retencja 14 dni | PVC: vault-backup | Codziennie |
| **Docker obrazy** | GitHub Actions po każdym push do main | GHCR | Każdy commit |

### 9.12 Gdzie są przechowywane sekrety i certyfikaty

```
PRZECHOWYWANIE SEKRETÓW

  VAULT (namespace: davtro02)
   /vault/data/ (PVC 2Gi)
    - bootstrap-keys (unseal key + root token, chmod 600)
    - raft/ (stan Vault: KV, auth, policies)

  KUBERNETES SECRETS (namespace: davtro02)
   davtro-secrets: DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD
   fastapi-db-creds: username, password (dynamiczne)
   message-processor-db-creds: username, password (dynamiczne)
   davtro-tls: tls.crt, tls.key (auto-rotowane)
   spark-tls: tls.crt, tls.key (auto-rotowane)
   fastapi-mtls: tls.crt, tls.key (auto-rotowane, client/server auth)
   message-processor-mtls: tls.crt, tls.key (auto-rotowane, client/server auth)
   spring-app-mtls: tls.crt, tls.key (auto-rotowane, client/server auth)

  KUBERNETES SECRETS (namespace: cert-manager)
   cert-manager-vault-token: token (Vault auth dla cert-manager)

  PVC (namespace: davtro02)
   vault-backup: snapshot-*.snap (codziennie, retencja 14 dni)
```


### 9.13 Potwierdzenie działania (stan aktualny)

```
CERTYFIKATY:
  davtro-tls: Ready=True, CN=davtro.local, Issuer=vault-issuer, Expiry=2026-12-11
  spark-tls:  Ready=True, CN=spark.davtro.local, Issuer=vault-issuer, Expiry=2026-12-11

CLUSTERISSUER:
  vault-issuer: Ready=True (token auth)
  vault-issuer-internal: Ready=True (token auth, path pki/sign/davtro-internal)

CERTYFIKATY mTLS (issuer: vault-issuer-internal):
  fastapi-mtls:            Ready=True, CN=fastapi-web-app.davtro02.svc,    Issuer=vault-issuer-internal, Expiry=2026-10-14
  message-processor-mtls:  Ready=True, CN=message-processor.davtro02.svc,  Issuer=vault-issuer-internal, Expiry=2026-10-14
  spring-app-mtls:         Ready=True, CN=spring-app.davtro02.svc,         Issuer=vault-issuer-internal, Expiry=2026-10-14

ARGODCD:
  davtro-website: SYNC=Synced, HEALTH=Healthy

PODY (23 Running, 0 Errors):
  fastapi-web-app (3 replicas), frontend (2), message-processor, spring-app
  postgres-db, redis, kafka-kraft, kafka-ui
  vault-0, vault-bootstrap
  spark-master, spark-worker (2)
  prometheus, grafana, loki, tempo, promtail
    postgres-exporter, kafka-exporter, node-exporter
  pgadmin
```

### 9.14 Szyfrowanie PII — Vault Transit Engine (Krok 4)

**Stan:** ✅ Aktywne. Wrażliwe dane osobowe (imię gościa, e-mail, telefon) są
szyfrowane **w locie** w Vault Transit Engine (klucz `davtro-app`, `aes256-gcm96`,
auto-rotacja co 30 dni) przed zapisem do PostgreSQL, a odszyfrowywane przy odczycie.

**Artykuły w repo:**
- `backend-fastapi/app/transit_client.py` — klient Python (Kubernetes auth → Vault,
  token odswieżany po 403/TTL, retry po wygaśnięciu).
- `backend-fastapi/requirements.txt` — `requests==2.32.3` (klient HTTP do Transit).
- `manifests/base/transit-helpers.yaml` — ConfigMap `transit-helpers` (skrypty
  `transit_encrypt`/`transit_decrypt`/`transit_datakey` + `vault_agent_config.hcl`)
  oraz `SecretStore vault-transit`.
- `manifests/base/vault-bootstrap.yaml` — konfiguruje Vault: `vault secrets enable
  transit`, klucz `davtro-app`, politykę `davtro-transit` i K8s-rolę `davtro-transit`
  (SA `davtro-sa`, TTL 1h).

**Jak szyfruje w FastAPI (`backend-fastapi/app/main.py`):**
- w `create_booking()` przed `INSERT INTO bookings` pola `guest_name`, `email`,
  `phone` przechodzą przez `encrypt_pii()` → w bazie zapisywane jako `vault:v1:...`
  (ciphertext). Kafka i Redis dalej dostają plaintext — `message-processor`
  wysyła z nich e-maile potwierdzające i faktury.
- w `get_bookings()` pola `guest_name`, `email` są deszyfrowane przez `decrypt_pii()`
  (stare wiersze w plaintextie zwracane bez zmian — recognizowane po braku prefiksu
  `vault:v`).

**Env w deploymentie (`deployment.yaml`):**
| Env | Wartość |
|---|---|
| `VAULT_TRANSIT_ADDR` | `https://vault.davtro02.svc.cluster.local:8203` (od KROK 9/10) |
| `VAULT_TRANSIT_CA_FILE` | `/etc/vault-tls/ca.crt` (CA `davtro-vault-ca` z sekretu `vault-tls`) |
| `VAULT_TRANSIT_KEY` | `davtro-app` |
| `VAULT_TRANSIT_AUTH_ROLE` | `davtro-transit` |
| `VAULT_TRANSIT_TIMEOUT` | `30` (login robi TokenReview na apiserverze – 10 s bywało za mało) |
| `VAULT_TRANSIT_ENABLED` | `true` (można wyłączyć, by zapisywać plaintext) |

**FIX (KROK 9/10) — dlaczego właściciel widział `vault:v1:...` w „Moje Rezerwacje”:**
Po przełączeniu Vaulta na TLS (`:8203`) `verify` (CA) przekazywało tylko
`TransitClient._request()`, a `VaultTokenProvider.get_token()` wołało
`requests.post()` **bez `verify=`** — czyli z systemowym store CA. Cert serwera
Vaulta pochodzi z wewnętrznego CA `davtro-vault-ca`, więc logowanie
`auth/kubernetes/login` padało z:

```
SSLError(... CERTIFICATE_VERIFY_FAILED ... unable to get local issuer certificate)
```

Skutek: brak tokena → `encrypt_pii()`/`decrypt_pii()` zawsze wracały z fallbacku,
czyli panel „Moje Rezerwacje” pokazywał surowy ciphertext zamiast danych gościa
(obce rezerwacje maskowane prawidłowo, bo tam deszyfrowanie w ogóle nie jest
wywoływane). Poprawka: adres + `verify` są liczone w jednym miejscu
(`vault_tls_config()` w `transit_client.py`) i używane przez **oba** klienty
(login oraz `transit/*`), plus ostrzeżenie w logu, gdy plik CA nie istnieje.
Diagnostyka: `python -c "import requests; print(requests.get('https://vault.davtro02.svc.cluster.local:8203/v1/sys/health', verify='/etc/vault-tls/ca.crt').status_code)"`.

**Fail-safe:** gdy Vault lub auth jest chwilowo niedostępny (startup, rotacja tokena,
awaria), aplikacja **loguje błąd i zapisuje odczytane/zapisywane dane jako plaintext**
— API nie przestaje działać. Dzięki temu nie ma ryzyka, że awaria sejfu zerwie
rezerwacje. Szyfrowanie wznawia się automatycznie po przywróceniu łączności.

**Polityka Vault (`davtro-transit.hcl`):**
```
path "transit/encrypt/davtro-app" { capabilities = ["update"] }
path "transit/decrypt/davtro-app" { capabilities = ["update"] }
path "transit/rewrap/davtro-app"  { capabilities = ["update"] }
path "transit/datakey/davtro-app" { capabilities = ["update"] }
path "davtro/data/*"              { capabilities = ["read"] }
path "database/creds/davtro-app-rw" { capabilities = ["read"] }
```

**Weryfikacja po wdrożeniu:**
```bash
# healthcheck pokaże "transit": true
kubectl -n davtro02 port-forward svc/fastapi-web-app 8080
curl -s http://localhost:8080/api/health

# utwórz rezerwację...
curl -X POST http://localhost:8080/api/bookings \
  -H 'Content-Type: application/json' \
  -d '{"property_id":1,"guest_name":"Jan Kowalski","email":"jk@example.com","phone":"+48123456789","guests":2,"check_in":"2026-01-01","check_out":"2026-01-05","total_price":1000}'

# ...i sprawdź, że w DB email jest zaszyfrowany (vault:v1:...), a nie plaintext:
kubectl -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -c \
  'SELECT id, guest_name, email, phone FROM bookings LIMIT 1;'
```
Po poprawnym wdrożeniu `email` powinno zaczynać się od `vault:v1:` — a w odpowiedzi
`GET /api/bookings` ponownie będzie to czytelny adres e-mail.


**Wyciganie haseł postgresql i aplikacji:**
```bash
# ... hasło do bazy postgresql
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' 2>&1 | base64 -d; echo; echo ---USER---; /snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_USER}' 2>&1 | base64 -d; echo

# ... wyciganie haseł admin dla app: platforma wynajmu krótkoterminowego
kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d; echo
```


---

# KROK 5/5b (Auth) – logowanie rezerwujących + hasło admina z Vaulta

## Logowanie i prywatność danych gości
- Rezerwacja wymaga zalogowania (`POST /api/bookings` -> 401 bez tokenu).
- Sesje: token w Redis (`session:<token>`, TTL 24 h), przesyłany jako `Authorization: Bearer`.
- Hasła: PBKDF2-HMAC-SHA256 (260 tys. iteracji, losowa sól) – `backend-fastapi/app/auth.py`, stdlib, zero nowych zależności.
- Endpointy: `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`.
- Prywatność: pełne dane gościa (imię, e-mail, telefon, kwota) widzi **tylko właściciel rezerwacji i admin**; pozostali dostają wiersz zamaskowany ("Zastrzeżone", kwota "–"). Daty zostają widoczne (kalendarz dostępności).
- Własne rezerwacje dostają odznakę **"Moja rezerwacja"** (flaga `mine` z API).
- Zakładka Admin dla zwykłego użytkownika to "Moje Rezerwacje" (tylko admin widzi pełny panel).
- Kalendarz per nieruchomość: combobox "Nieruchomość" w formularzu rezerwacji przełącza kalendarz (czerwone dni = zajęte dla danej nieruchomości).

## Schemat bazy (migracje automatyczne w `init_db`)
- Tabela `users` (username UNIQUE, password_hash, role user/admin, full_name+email szyfrowane Vault Transitem).
- Kolumny `bookings.user_id` / `bookings.username` – powiązanie rezerwacji z kontem.
- Świeże instalacje: kolumny są od razu w `CREATE TABLE`; istniejące bazy: `vault-bootstrap` robi idempotentny `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` jako właściciel bazy (dynamiczne credsy z Vaulta nie mają praw ALTER).
- **Backfill**: rezerwacje powstałe przed migracją są przypisywane do kont po e-mailu gościa (Vault Transit deszyfruje obie strony) – log: `init_db: backfill - przypisano N rezerwacji do kont`.

## Hasło admina – WYŁĄCZNIE z Vaulta (zero haseł w repo)
- Kolejność pobierania: plik `ADMIN_PASSWORD_FILE` (ESO/Vault) -> env `ADMIN_PASSWORD` (z Secretu `davtro-secrets`) -> **brak? = losowe generowane przy starcie** (jednorazowo widoczne w logu, jak `DB_PASSWORD` w bootstrapie).
- Bootstrap generuje `davtro/auth` (ADMIN_PASSWORD, 24 znaki) jeśli klucz nie istnieje; istniejący NIGDY nie jest nadpisywany.
- ESO: `external-secrets.yaml` dociąga `ADMIN_PASSWORD` z KV `davtro/auth` do `davtro-secrets` (deployment ma to w `envFrom`).
- Szybki test / zmiana hasła ręcznie:
```bash
vault kv put davtro/auth ADMIN_PASSWORD='TwojeSilneHaslo'
kubectl -n davtro02 annotate externalsecret davtro-secrets external-secrets.io/force-sync=$(date +%s) --overwrite
kubectl -n davtro02 rollout restart deploy/fastapi-web-app
```
- Konto admin seeduje się, gdy go nie ma (również awaryjnie przy próbie logowania).

## Zmiana hasła z UI
- Każdy zalogowany: sekcja "Zaloguj" -> karta "Zmiana własnego hasła" (`POST /api/auth/change-password`, wymaga aktualnego hasła, min. 6 znaków).
- Admin: zakładka Admin -> karta "Zmiana hasła użytkownika" (`POST /api/auth/admin/set-password`, 403 dla nie-admina) – ustawia hasło dowolnemu kontu.

# KROK 7 – alerty o wygasających certyfikatach (cert-expiry-exporter)

Cert-manager + Vault PKI renewuje certyfikaty automatycznie (ingress 90d/renew 15d, mTLS 30d/renew 7d). Nowy eksporter daje **widoczność**, gdyby renew się nie wydarzył:

- `manifests/base/cert-expiry-exporter.yaml`: eksporter (Python stdlib) skanuje co 60 s Secrety `kubernetes.io/tls` w `davtro02` i wystawia metryki:
  - `davtro_cert_not_after_seconds{secret=...}` – unix timestamp wygaśnięcia,
  - `davtro_cert_days_remaining{secret=...}` – dni do końca TTL.
  Własny ServiceAccount + Role (tylko `get/list secrets` w namespace) – minimalne uprawnienia.
- `prometheus.yaml`: scrape job `cert-expiry-exporter:9887` + `rule_files: cert-alerts.yml` z alertami:

| Alert | Próg | Poziom |
|---|---|---|
| `DavtroCertExpiringSoon` | < 14 dni | warning |
| `DavtroCertExpiringCritical` | < 3 dni | critical |
| `DavtroCertExpired` | <= 0 (wygasł) | critical |

- Alerty widoczne w Prometheus UI (`/alerts`, port 9090); po dołożeniu Alertmanagera ruszą powiadomienia.
- Test:
```bash
kubectl -n davtro02 port-forward svc/cert-expiry-exporter 9887:9887 &
curl -s localhost:9887/metrics
```

# Dostęp HTTPS z LAN – `scripts/port-forward.sh`
```bash
./scripts/port-forward.sh https-fastapi  8443   # https://<IP>:8443 (Ingress, davtro-tls)
./scripts/port-forward.sh https-frontend 8444   # https://<IP>:8444 (Ingress, davtro-tls)
./scripts/port-forward.sh https-spring   8445   # https://<IP>:8445 (Ingress)
./scripts/port-forward.sh https-vault    8243   # Vault (wyłącznie HTTPS)
```
Certy `davtro-tls` podpisuje Vault PKI przez cert-manager i sam je renewuje; w przeglądarce zaakceptuj self-signed CA przy pierwszym wejściu.



---

# KROK 8 – Alertmanager (powiadomienia email z alertow)

- `manifests/base/alertmanager.yaml`: Deployment `prom/alertmanager` + Service `alertmanager:9093`.
- **Sekrety SMTP nie sa w ConfigMapie**: `alertmanager.yml` jest TEMPLATEM, a `start.sh` podstawia przy starcie `SMTP_HOST/PORT/USER/PASSWORD` (z Vaulta przez ESO, Secret `davtro-secrets`) i `FROM_EMAIL`. Odbiorca: env `ALERT_EMAIL_TO` (domyslnie FROM_EMAIL).
- Bez skonfigurowanego SMTP alerty sa widoczne w UI Alertmanagera (port 9093), email ruszy po ustawieniu sekretow SMTP w Vault (`vault kv put davtro/smtp SMTP_HOST=... SMTP_USER=... SMTP_PASSWORD=...` + restart).
- Prometheus: `alerting.alertmanagers -> alertmanager:9093`; nowa grupa regul `target-health` - alert `DavtroTargetDown` gdy scrape target (fastapi/postgres-exporter/kafka-exporter/node-exporter/cert-expiry) lezy 5 min.
- Routing: severity=critical -> receiver email-critical (grupowanie po alertname+secret, repeat 4h).
- UI: `./scripts/port-forward.sh` (nowa linia `start alertmanager 9093`) albo bezposrednio `kubectl -n davtro02 port-forward svc/alertmanager 9093:9093` -> http://localhost:9093
- Test: `amtool` nie jest potrzebny - wystarczy wymusic alert: tymczasowo obniz prog w `cert-alerts.yml` albo wylacz pod cert-expiry-exporter (pojawi sie `DavtroTargetDown` i mail).

# Roadmapa TLS (Etap 4+ – do zrobienia)
- [x] Alertmanager (email) dla regul `cert-expiry` i `target-health` (KROK 8).
- [x] Vault HTTPS: listener TLS :8203, bez HTTP :8200 (KROK 10).
- [ ] Kafka listener SSL (cert z Vault PKI, mTLS producent/konsument; java-app + fastapi + kafka-ui + exporter).
- [ ] Redis TLS (wymaga obrazu z TLS lub sidecar stunnel – stock `redis` nie ma TLS).
- [ ] Dynamiczne credsy Redis/Kafka z Vaulta (redis-database / SASL-SCRAM).
- [ ] Auto-unseal Vaulta (cloud KMS / transit) zamiast klucza na PVC.

---

# KROK 9–10 – Vault HTTPS, finalnie TLS-only (:8203)

- **Serwer** (`vault.yaml`): od KROK 10 istnieje wyłącznie listener TLS `0.0.0.0:8203` (`tls_cert_file=/vault/tls/tls.crt`, min TLS 1.2). Port HTTP `8200` nie występuje w ConfigMap, kontenerze ani Service; `8201` pozostaje wewnętrznym `cluster_address` dla Raft.
- **Certyfikat SERWERA Vaulta** (`vault-server-tls.yaml`) — **NIE z Vault PKI!** Cert-manager podpisuje przez Vault PKI (`pki/sign/...`), czyli musi najpierw połączyć się z działającym Vaultem, a Vault bez własnego certyfikatu nie wstaje z listenerem TLS — błędne koło. Rozwiązanie: własne bootstrapowe CA (`Issuer vault-selfsigned` → `Certificate vault-ca` isCA, 10 lat, `rotationPolicy: Never`) → `Issuer vault-ca` → `Certificate vault-tls` (CN `vault.davtro02.svc` + SAN-y `vault.davtro02.svc`, `vault.davtro02.svc.cluster.local`, `vault`, `vault-0...vault-5`). Sekret `vault-tls` zawiera `tls.crt`/`tls.key`/`ca.crt`. Sekret istnieje **zanim** Vault wystartuje, a długie TTL + `rotationPolicy: Never` = stabilne zaufanie przy rotacji liścia. Certy usług wewnętrznych (mTLS fastapi/spring, Ingress) **dalej** wystawia PKI Vaulta (`pki/davtro-internal`) — bootstrapowe CA służy wyłącznie do TLS servera Vaulta.
- **Klienci przelaczeni na `https://vault.davtro02.svc.cluster.local:8203`:**
  - ESO: `secret-store.yaml` (2 store'y), `external-secrets-db-dynamic.yaml` (VaultDynamicSecret) - `caProvider` typ Secret `vault-tls` key `ca.crt` (CA czytane z sekretu, nic w Git).
  - FastAPI: `deployment.yaml` - env `VAULT_TRANSIT_ADDR=https...:8203`, `VAULT_TRANSIT_CA_FILE=/etc/vault-tls/ca.crt`, mount `vault-tls`; `transit_client.py` weryfikuje CA (fail-safe: bez certu fallback plaintext z logiem, jak KROK 4).
  - **FIX (transit po TLS):** `verify` jest liczony w `vault_tls_config()` i podawany **także w loginie** `auth/kubernetes/login` (`VaultTokenProvider`) - wcześniej login szedł z systemowym store CA i padał na `unable to get local issuer certificate`, przez co `encrypt_pii`/`decrypt_pii` były zawsze w fallbacku (panel pokazywał `vault:v1:...`, a nowe dane zapisywały się jako plaintext).
  - Spring + message-processor: te same env + mount (po stronie kodu Java wymaga wsparcia CA_FILE - do weryfikacji przy wdrozeniu).
  - transit-helpers (`transit-helpers.yaml`): `SecretStore/vault-transit` — `VAULT_ADDR`/`server: https://vault.davtro02.svc.cluster.local:8203` + `caProvider { type: Secret, name: vault-tls, key: ca.crt }` (ten sam mechanizm co ESO, sekret CA czytany z K8s, nic w Git).
  - Snapshot CronJob: `VAULT_ADDR=https...:8203` + `VAULT_CACERT` + mount.
- **KROK 10 — Vault TLS-only (zamknięcie dual-listenera):**
  - `vault.yaml` ma wyłącznie listener TLS `0.0.0.0:8203`; port `8200` nie jest już w ConfigMap, kontenerze ani Service.
  - Secret `vault-tls` jest wymaganym volumeMount. Bez niego kubelet nie uruchamia Vaulta, więc nie istnieje fallback HTTP.
  - Bootstrap łączy się przez `https://vault.davtro02.svc.cluster.local:8203` i używa `VAULT_CACERT=/etc/vault-tls/ca.crt`.
  - `ClusterIssuer/vault-issuer` i `vault-issuer-internal` używają HTTPS :8203 oraz `inject-ca-from-secret: davtro02/vault-ca`; cainjector aktualizuje `caBundle` po zmianie CA.
  - NetworkPolicy przepuszcza do Vaulta tylko TCP 8203 dla ESO i cert-managera.
  - Dostęp lokalny: `./scripts/port-forward.sh https-vault 8243` (forward 8243 → 8203), z CA z `vault-tls`.
### Automatyczne odblokowanie po restarcie Vaulta

Bootstrap (`vault-bootstrap.yaml`) działa jako Deployment z pętlą co 60 s i automatycznie wykonuje `vault operator unseal` przy stanie `sealed=true`. Ważne: `vault status` zwraca kod wyjścia `2` dla zapieczętowanego Vaulta — jest to prawidłowa odpowiedź, nie błąd połączenia. Skrypt `read_status` traktuje kody `0` i `2` jako odpowiedź serwera, a dopiero inne kody jako błąd TLS/sieci.

Po odblokowaniu bootstrap sprawdza token z `/vault/data/bootstrap-keys` przez `vault token lookup`. Jeżeli token jest pusty lub nieaktualny, nie wykonuje dalszej konfiguracji i zapisuje konkretny komunikat zamiast ogólnego `BLAD`.

Aby wymusić ponowienie pętli po wdrożeniu poprawki:

```bash
kubectl -n davtro02 rollout restart deployment/vault-bootstrap
kubectl -n davtro02 logs deployment/vault-bootstrap -c ensure --tail=50
```

W prawidłowym stanie log powinien zawierać `OK - nastepny check za 60s`. Plik `bootstrap-keys` ma pozostać na PVC `vault-data-vault-0`; nie należy go usuwać ani ponownie inicjalizować Vaulta.


1. **NetworkPolicy `allow-eso-to-vault` musi przepuszczać TCP 8203** (`network-policies.yaml`).
   Po przełączeniu klientów na `:8203` samo `namespaceSelector` na `:8200/8201` było za mało —
   ESO dostawał `context deadline exceeded` (policy `default-deny` odrzucała połączenie), więc
   `davtro-secrets` nie powstawał i kaskada: pody postgres / alertmanager / pgadmin / spring-app /
   postgres-exporter / fastapi wpadały w `CreateContainerConfigError` (brakujący secret) lub `CrashLoopBackOff`.
2. **Każdy store wskazujący na `https://...:8203` musi mieć `caProvider`** wskazujący na sekret `vault-tls`, klucz `ca.crt`
   (`secret-store.yaml` ×2, `transit-helpers.yaml` → `SecretStore/vault-transit`).
   Bez tego: `x509: certificate signed by unknown authority` → `SecretStore` = `Degraded`.
3. **Pułapka GitOps**: obie poprawki były już w `main`, ale `vault-transit` bez `caProvider` blokował
   `argocd` sync (`Failed` po 5 retryach) → ArgoCD nigdy nie dostarczył poprawek do klastra,
   a live namespace pozostawał stary (tzw. GitOps deadlock: błąd w sync nie da się naprawić przez sync).
   Rozwiązanie tymczasowe: ręczny `kubectl apply` plików, aż ArgoCD wróci do `Synced/Healthy`.
4. **`namespaceSelector` bez `podSelector`** w elemencie `from` — kombinacja obu w jednym elemencie to AND,
   czyli wymagałaby podu będącego jednocześnie w ns ESO i ns target; stąd dwa osobne elementy `from`.

**Status weryfikacji (live, ns `davtro02`)**: ArgoCD `davtro-website` = `Synced/Healthy`; wszystkie pody `Running/Completed`;
`SecretStore` `vault-backend` / `vault-dynamic` / `vault-transit` = `Valid=True`; wszystkie `ExternalSecret` = `SecretSynced=True`;
`Certificate vault-tls` i `vault-ca` = `True`. Sprawdzenie TLS od strony poda:

```bash
kubectl -n davtro02 exec vault-0 -- vault status \
  -address=https://127.0.0.1:8203 -cacert=/vault/tls/ca.crt
```



# KROK 11 (Kafka mTLS) — dual listener i automatyczne certyfikaty

Kafka działa równolegle na dwóch listenerach:

- `kafka-kraft:9092` — PLAINTEXT, pozostawiony pomocniczo dla Kafka UI, eksportera i inicjalizacji topiców,
- `kafka-kraft:9094` — mTLS dla FastAPI, Spring i message-processora.

Port `9093` pozostaje wyłącznie listenerem controllera KRaft. Certyfikat brokera `kafka-server-tls` oraz istniejące certyfikaty klientów są wystawiane przez `vault-issuer-internal` i odnawiane przez cert-manager. Broker wymaga certyfikatu klienta (`ssl.client.auth=required`); aplikacje montują certyfikat i CA pod `/etc/mtls`.

Po wdrożeniu kolejność testu:

1. sprawdzić `Certificate/kafka-server-tls` i Secret `kafka-server-tls`,
2. sprawdzić, że `kafka-kraft-0` uruchomił się i ma port `9094`,
3. potwierdzić topic na dotychczasowym `9092`,
4. potwierdzić, że FastAPI/Spring/message-processor łączą się przez `9094`.

Dopiero po potwierdzeniu pipeline można rozważyć usunięcie listenera PLAINTEXT `9092` oraz przełączenie narzędzi pomocniczych na mTLS.


EOF

# ============================================
# FINALIZE
# ============================================

echo "=== DavTro Rentals - Setup Complete ==="
echo "Project created in: ${PROJECT_NAME}/"
echo "Next steps:"
echo "  1. cd ${PROJECT_NAME}"
echo "  2. Review manifests/base/secret.yaml and configure real secrets or Vault"
echo "  3. Build images: docker build -t davtro-fastapi ./backend-fastapi"
echo "  4. Apply to K8s: kubectl apply -k manifests/overlays/production"
echo "  5. Or use ArgoCD: kubectl apply -f argocd/application.yaml -n argocd"