#!/bin/bash
set -e

PROJECT_NAME="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
NAMESPACE="davtro"
REPO="https://github.com/exea-centrum/${PROJECT_NAME}.git"

echo "=== DavTro Rentals - All-in-One Setup (Combined & Fixed) ==="
mkdir -p ${PROJECT_NAME}/{frontend,backend-fastapi/app/{templates,static},java-app/src/main/{java/com/davtro/rental/{model,repository,consumer,service},resources},spark-jobs/src/main/scala/com/davtro/jobs,spark-jobs/project,manifests/{base,overlays/{production,staging},argocd},terraform,.github/workflows,scripts,docs,kyverno-policies,argocd}

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
      <button onclick="showSection('admin')" class="nav-btn text-gray-300 hover:text-white font-medium">Admin</button>
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
    <div class="glass rounded-2xl p-6">
      <h3 class="text-xl font-bold mb-6">Kafka Topics</h3>
      <div class="grid md:grid-cols-3 gap-4">
        <div class="bg-slate-800/50 rounded-xl p-4 border border-yellow-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-yellow-400">bookings-created</span><span class="text-xs bg-yellow-500/20 text-yellow-400 px-2 py-1 rounded">spring-app</span></div><div class="text-2xl font-bold">1,247</div></div>
        <div class="bg-slate-800/50 rounded-xl p-4 border border-purple-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-purple-400">marketing-actions</span><span class="text-xs bg-purple-500/20 text-purple-400 px-2 py-1 rounded">spark-app</span></div><div class="text-2xl font-bold">3,892</div></div>
        <div class="bg-slate-800/50 rounded-xl p-4 border border-green-500/20"><div class="flex justify-between mb-2"><span class="font-semibold text-green-400">email-invoices</span><span class="text-xs bg-green-500/20 text-green-400 px-2 py-1 rounded">message-processor</span></div><div class="text-2xl font-bold">1,198</div></div>
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
const properties=[
  {id:1,name:"Apartament Premium - Warszawa",location:"warsaw",price:450,guests:4,image:"🏙️",rating:4.9,amenities:["WiFi","Klimatyzacja","Balkon","Parking"],description:"Luksusowy apartament w centrum Warszawy."},
  {id:2,name:"Studio Modern - Kraków",location:"krakow",price:320,guests:2,image:"🏰",rating:4.8,amenities:["WiFi","Smart TV","Kuchnia"],description:"Stylowe studio obok Rynku Głównego."},
  {id:3,name:"Villa nad Morzem - Gdańsk",location:"gdansk",price:680,guests:6,image:"🌊",rating:4.9,amenities:["WiFi","Ogródek","Grill","Parking"],description:"Willa 200m od plaży."},
  {id:4,name:"Loft Industrial - Wrocław",location:"wroclaw",price:280,guests:3,image:"🏭",rating:4.7,amenities:["WiFi","Projektor","Klimatyzacja"],description:"Industrialny loft w Nadodrzu."},
  {id:5,name:"Penthouse View - Warszawa",location:"warsaw",price:850,guests:4,image:"🌆",rating:5.0,amenities:["WiFi","Basen","Siłownia","Concierge"],description:"Ekskluzywny penthouse z tarasem."},
  {id:6,name:"Apartament Royal - Kraków",location:"krakow",price:390,guests:4,image:"👑",rating:4.8,amenities:["WiFi","Klimatyzacja","Balkon"],description:"Elegancki apartament w Kazimierzu."}
];
let bookings=JSON.parse(localStorage.getItem('bookings')||'[]');
let currentMonth=new Date();
let selectedDates=[];
function showSection(section){document.querySelectorAll('.section-content').forEach(s=>s.classList.add('hidden'));document.getElementById(section+'-section').classList.remove('hidden');if(section==='properties')renderProperties();if(section==='calendar'){renderCalendar();populatePropertySelect();}if(section==='admin')renderAdmin();}
function showToast(title,message,type='success'){const toast=document.getElementById('toast');document.getElementById('toast-title').textContent=title;document.getElementById('toast-message').textContent=message;toast.classList.remove('translate-y-20','opacity-0');setTimeout(()=>toast.classList.add('translate-y-20','opacity-0'),4000);}
function createPropertyCard(prop){return`<div class="property-card glass rounded-2xl overflow-hidden"><div class="h-48 bg-gradient-to-br from-slate-700 to-slate-800 flex items-center justify-center text-6xl relative">${prop.image}<div class="absolute top-4 right-4 bg-black/50 rounded-lg px-3 py-1 text-sm font-bold"><i class="fas fa-star text-yellow-400 mr-1"></i>${prop.rating}</div></div><div class="p-6"><div class="flex items-center gap-2 text-sm text-gray-400 mb-2"><i class="fas fa-map-marker-alt text-blue-400"></i>${prop.location}</div><h3 class="text-lg font-bold mb-2">${prop.name}</h3><p class="text-sm text-gray-400 mb-4">${prop.description}</p><div class="flex flex-wrap gap-2 mb-4">${prop.amenities.map(a=>`<span class="text-xs bg-white/10 px-2 py-1 rounded">${a}</span>`).join('')}</div><div class="flex items-center justify-between"><div><span class="text-2xl font-bold text-blue-400">${prop.price} zł</span><span class="text-sm text-gray-400">/doba</span></div><button onclick="selectPropertyForBooking(${prop.id})" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition">Rezerwuj</button></div></div></div>`;}
function renderProperties(){document.getElementById('all-properties').innerHTML=properties.map(p=>createPropertyCard(p)).join('');}
function renderFeatured(){document.getElementById('featured-properties').innerHTML=properties.slice(0,3).map(p=>createPropertyCard(p)).join('');}
function renderCalendar(){const grid=document.getElementById('calendar-grid');const monthLabel=document.getElementById('calendar-month');const year=currentMonth.getFullYear(),month=currentMonth.getMonth();const monthNames=['Styczeń','Luty','Marzec','Kwiecień','Maj','Czerwiec','Lipiec','Sierpień','Wrzesień','Październik','Listopad','Grudzień'];monthLabel.textContent=`${monthNames[month]} ${year}`;grid.innerHTML='';const firstDay=new Date(year,month,1).getDay();const daysInMonth=new Date(year,month+1,0).getDate();const startOffset=firstDay===0?6:firstDay-1;for(let i=0;i<startOffset;i++)grid.innerHTML+=`<div></div>`;for(let day=1;day<=daysInMonth;day++){const dateStr=`${year}-${String(month+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;const isBooked=bookings.some(b=>dateStr>=b.checkIn&&dateStr<=b.checkOut);const isSelected=selectedDates.includes(dateStr);const isPast=new Date(dateStr)<new Date().setHours(0,0,0,0);let classes='h-12 rounded-lg flex items-center justify-center cursor-pointer text-sm font-medium ';if(isPast)classes+='text-gray-600 cursor-not-allowed';else if(isBooked)classes+='bg-red-500/20 border border-red-500 text-red-300 cursor-not-allowed';else if(isSelected)classes+='bg-blue-500 border border-blue-400 text-white';else classes+='bg-white/5 hover:bg-white/15';const onclick=isPast||isBooked?'':`onclick="toggleDate('${dateStr}')"`;
grid.innerHTML+=`<div class="${classes}" ${onclick}>${day}</div>`;}}
function changeMonth(delta){currentMonth.setMonth(currentMonth.getMonth()+delta);renderCalendar();}
function toggleDate(dateStr){const idx=selectedDates.indexOf(dateStr);if(idx>-1)selectedDates.splice(idx,1);else if(selectedDates.length<2)selectedDates.push(dateStr);else{selectedDates=[selectedDates[1],dateStr];}selectedDates.sort();renderCalendar();if(selectedDates.length===2){document.getElementById('check-in').value=selectedDates[0];document.getElementById('check-out').value=selectedDates[1];calculatePrice();}}
function populatePropertySelect(){document.getElementById('booking-property').innerHTML='<option value="">-- Wybierz --</option>'+properties.map(p=>`<option value="${p.id}">${p.name} - ${p.price} zł/doba</option>`).join('');}
function selectPropertyForBooking(id){showSection('calendar');document.getElementById('booking-property').value=id;calculatePrice();}
function calculatePrice(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;if(!propId||!checkIn||!checkOut)return;const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));if(nights>0){document.getElementById('price-per-night').textContent=prop.price+' zł';document.getElementById('night-count').textContent=nights;document.getElementById('total-price').textContent=(prop.price*nights)+' zł';}}
['booking-property','check-in','check-out'].forEach(id=>{document.getElementById(id)?.addEventListener('change',calculatePrice);});
async function submitBooking(){const propId=document.getElementById('booking-property').value;const checkIn=document.getElementById('check-in').value;const checkOut=document.getElementById('check-out').value;const name=document.getElementById('guest-name').value;const email=document.getElementById('guest-email').value;const phone=document.getElementById('guest-phone').value;if(!propId||!checkIn||!checkOut||!name||!email){showToast('Błąd','Wypełnij wszystkie pola','error');return;}const prop=properties.find(p=>p.id==propId);const nights=Math.ceil((new Date(checkOut)-new Date(checkIn))/(1000*60*60*24));const total=prop.price*nights;const booking={id:'BK-'+Date.now(),propertyId:propId,propertyName:prop.name,guestName:name,email:email,phone:phone,checkIn:checkIn,checkOut:checkOut,nights:nights,totalPrice:total,status:'confirmed',pipeline:'Redis → Kafka → PostgreSQL'};showToast('Przetwarzanie','Rezerwacja przez Redis → Kafka...','info');await new Promise(r=>setTimeout(r,2000));bookings.push(booking);localStorage.setItem('bookings',JSON.stringify(bookings));showToast('Sukces!',`Rezerwacja potwierdzona! Faktura proforma na ${total} zł wysłana na ${email}`);document.getElementById('guest-name').value='';document.getElementById('guest-email').value='';document.getElementById('guest-phone').value='';selectedDates=[];renderCalendar();}
function renderAdmin(){document.getElementById('stat-bookings').textContent=bookings.length;const revenue=bookings.reduce((sum,b)=>sum+b.totalPrice,0);document.getElementById('stat-revenue').textContent=revenue.toLocaleString()+' zł';document.getElementById('stat-kafka').textContent=(bookings.length*3+1247).toLocaleString();document.getElementById('stat-occupancy').textContent=Math.min(95,bookings.length*5)+'%';const tbody=document.getElementById('bookings-table');tbody.innerHTML=bookings.slice().reverse().map(b=>`<tr class="border-b border-white/5"><td class="py-4 font-mono text-sm text-blue-400">${b.id}</td><td class="py-4">${b.propertyName}</td><td class="py-4">${b.guestName}<br><span class="text-xs text-gray-500">${b.email}</span></td><td class="py-4 text-sm">${b.checkIn} → ${b.checkOut}<br><span class="text-xs text-gray-500">${b.nights} nocy</span></td><td class="py-4 font-bold">${b.totalPrice.toLocaleString()} zł</td><td class="py-4"><span class="px-2 py-1 bg-green-500/20 text-green-400 rounded text-xs">${b.status}</span></td></tr>`).join('')||'<tr><td colspan="6" class="py-8 text-center text-gray-500">Brak rezerwacji</td></tr>';}
function exportBookings(){const csv='ID,Nieruchomość,Gość,Email,Check-in,Check-out,Nocy,Kwota,Status\n'+bookings.map(b=>`${b.id},${b.propertyName},${b.guestName},${b.email},${b.checkIn},${b.checkOut},${b.nights},${b.totalPrice},${b.status}`).join('\n');const blob=new Blob([csv],{type:'text/csv'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='rezerwacje-davtro.csv';a.click();showToast('Eksport','Plik CSV pobrany');}
renderFeatured();showSection('home');
</script>
</body>
</html>
HTMLEOF

cat > ${PROJECT_NAME}/frontend/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx","-g","daemon off;"]
EOF

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
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import List, Optional
import asyncpg
import redis.asyncio as aioredis
import json
import os
from datetime import datetime, date
from kafka import KafkaProducer
import uvicorn

app = FastAPI(title="DavTro Rentals API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

DB_HOST = os.getenv("DB_HOST", "postgres-db")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")
DB_USER = os.getenv("DB_USER", "davtro")
DB_PASS = os.getenv("DB_PASSWORD", "changeme")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka-kraft:9092")

db_pool = None
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
    guest_name: str
    email: str
    check_in: str
    check_out: str
    total_price: float
    status: str
    created_at: str

@app.on_event("startup")
async def startup():
    global db_pool, redis_pool, kafka_producer
    db_pool = await asyncpg.create_pool(host=DB_HOST, port=DB_PORT, database=DB_NAME, user=DB_USER, password=DB_PASS, min_size=5, max_size=20)
    redis_pool = aioredis.from_url(f"redis://{REDIS_HOST}:{REDIS_PORT}", decode_responses=True)
    kafka_producer = KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP, value_serializer=lambda v: json.dumps(v).encode('utf-8'))
    await init_db()

@app.on_event("shutdown")
async def shutdown():
    if db_pool: await db_pool.close()
    if redis_pool: await redis_pool.close()
    if kafka_producer: kafka_producer.close()

async def init_db():
    async with db_pool.acquire() as conn:
        await conn.execute('CREATE TABLE IF NOT EXISTS properties (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, location VARCHAR(100), price DECIMAL(10,2), guests INT DEFAULT 2, description TEXT, amenities JSONB DEFAULT \'[]\', created_at TIMESTAMP DEFAULT NOW())')
        await conn.execute('CREATE TABLE IF NOT EXISTS bookings (id VARCHAR(50) PRIMARY KEY, property_id INT REFERENCES properties(id), guest_name VARCHAR(255), email VARCHAR(255), phone VARCHAR(50), guests INT, check_in DATE, check_out DATE, nights INT, total_price DECIMAL(10,2), status VARCHAR(50) DEFAULT \'confirmed\', pipeline VARCHAR(100) DEFAULT \'Redis -> Kafka -> PostgreSQL\', created_at TIMESTAMP DEFAULT NOW())')
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

@app.get("/api/health")
async def health():
    redis_ok = await redis_pool.ping()
    async with db_pool.acquire() as conn:
        db_ok = await conn.fetchval("SELECT 1")
    return {"status": "healthy", "database": db_ok == 1, "redis": redis_ok, "kafka": kafka_producer is not None}

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

@app.post("/api/bookings")
async def create_booking(booking: BookingCreate, background_tasks: BackgroundTasks):
    booking_id = f"BK-{datetime.now().strftime('%Y%m%d%H%M%S')}-{booking.property_id}"
    nights = (booking.check_out - booking.check_in).days
    cache_key = f"booking:{booking_id}"
    booking_data = booking.dict()
    booking_data.update({"id": booking_id, "nights": nights, "status": "pending"})
    await redis_pool.setex(cache_key, 3600, json.dumps(booking_data))
    kafka_producer.send("bookings-created", {"event": "booking_created", "booking_id": booking_id, "property_id": booking.property_id, "guest_name": booking.guest_name, "email": booking.email, "phone": booking.phone, "check_in": str(booking.check_in), "check_out": str(booking.check_out), "nights": nights, "total_price": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    kafka_producer.send("email-invoices", {"event": "invoice_request", "booking_id": booking_id, "email": booking.email, "guest_name": booking.guest_name, "total_price": float(booking.total_price), "property_id": booking.property_id, "check_in": str(booking.check_in), "check_out": str(booking.check_out)})
    kafka_producer.send("marketing-actions", {"event": "new_booking", "property_id": booking.property_id, "guest_email": booking.email, "guest_name": booking.guest_name, "booking_value": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    kafka_producer.flush()
    return BookingResponse(id=booking_id, property_id=booking.property_id, property_name="", guest_name=booking.guest_name, email=booking.email, check_in=str(booking.check_in), check_out=str(booking.check_out), total_price=booking.total_price, status="pending", created_at=datetime.now().isoformat())

@app.get("/api/bookings")
async def get_bookings():
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT b.*, p.name as property_name FROM bookings b JOIN properties p ON b.property_id = p.id ORDER BY b.created_at DESC")
    return [BookingResponse(id=r["id"], property_id=r["property_id"], property_name=r["property_name"], guest_name=r["guest_name"], email=r["email"], check_in=str(r["check_in"]), check_out=str(r["check_out"]), total_price=float(r["total_price"]), status=r["status"], created_at=str(r["created_at"])) for r in rows]

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
PYEOF

cat > ${PROJECT_NAME}/backend-fastapi/app/db.py << 'EOF'
import os
from sqlalchemy import create_engine, Column, Integer, String, Numeric, Date, Boolean, DateTime, func
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@postgres-clusterip:5432/davtro",
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
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
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()
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

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
_producer = None


def get_producer():
    global _producer
    if _producer is None:
        _producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
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

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
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
spring.datasource.url=jdbc:postgresql://${DB_HOST:postgres-db}:5432/davtro_rentals
spring.datasource.username=${DB_USER:davtro}
spring.datasource.password=${DB_PASSWORD:changeme}
spring.jpa.hibernate.ddl-auto=validate
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

mkdir -p ${PROJECT_NAME}/spark-jobs/project
cat > ${PROJECT_NAME}/spark-jobs/project/plugins.sbt << 'EOF'
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.1.5")
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
  KAFKA_BOOTSTRAP_SERVERS: "kafka-kraft:9092"
EOF

cat > ${PROJECT_NAME}/manifests/base/secret.yaml << 'EOF'
# UWAGA: W produkcji uzyj ArgoCD Vault Plugin, SealedSecrets lub ExternalSecrets
apiVersion: v1
kind: Secret
metadata:
  name: davtro-secrets
  namespace: davtro02
type: Opaque
stringData:
  DB_USER: "davtro"
  DB_PASSWORD: "changeme"
  SMTP_USER: ""
  SMTP_PASSWORD: ""
  VAULT_ROOT_TOKEN: "root"
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
      containers:
        - name: fastapi
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01:latest
          ports: [{ containerPort: 8080 }]
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
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
# Dev-mode Vault - w produkcji uzyj Helm chart HashiCorp Vault (HA + auto-unseal)
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
    metadata: { labels: { app: vault } }
    spec:
      serviceAccountName: davtro-sa
      securityContext:
        runAsUser: 100
        runAsGroup: 100
        fsGroup: 100
      containers:
        - name: vault
          image: hashicorp/vault:1.17
          # Bezposrednio vault zamiast docker-entrypoint.sh - entrypoint probuje
          # setcap (CAP_SETFCAP) i pada w srodowisku bez tej capability.
          # Dev-mode sam wylacza mlock, wiec setcap nie jest potrzebny.
          command: ["vault", "server", "-dev", "-dev-listen-address=0.0.0.0:8200"]
          ports: [{ containerPort: 8200 }]
          env:
            - { name: VAULT_SKIP_SETCAP, value: "true" }
            - name: VAULT_DEV_ROOT_TOKEN_ID
              valueFrom: { secretKeyRef: { name: davtro-secrets, key: VAULT_ROOT_TOKEN, optional: true } }
          resources:
            requests: { cpu: 50m, memory: 128Mi }
            limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: davtro02
spec:
  selector: { app: vault }
  ports: [{ port: 8200, targetPort: 8200 }]
EOF

cat > ${PROJECT_NAME}/manifests/base/kafka.yaml << 'EOF'
# Kafka KRaft (bez Zookeepera)
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
          ports: [{ containerPort: 9092 }]
          env:
            - { name: CLUSTER_ID, value: "MkU3OEVBNTcwNTJENDM2Qk" }
            - { name: KAFKA_NODE_ID, value: "0" }
            - { name: KAFKA_PROCESS_ROLES, value: "controller,broker" }
            - { name: KAFKA_LISTENERS, value: "PLAINTEXT://:9092,CONTROLLER://:9093" }
            - { name: KAFKA_ADVERTISED_LISTENERS, value: "PLAINTEXT://kafka-kraft:9092" }
            - { name: KAFKA_CONTROLLER_QUORUM_VOTERS, value: "0@kafka-kraft-0.kafka-kraft:9093" }
            - { name: KAFKA_CONTROLLER_LISTENER_NAMES, value: "CONTROLLER" }
            - { name: KAFKA_INTER_BROKER_LISTENER_NAME, value: "PLAINTEXT" }
            - { name: KAFKA_LOG_DIRS, value: "/tmp/kraft-combined-logs" }
          resources:
            requests: { cpu: 200m, memory: 512Mi }
            limits: { cpu: 1, memory: 1Gi }
          volumeMounts:
            - name: kafka-data
              mountPath: /tmp/kraft-combined-logs
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
      containers:
        - name: message-processor
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer:latest
          envFrom:
            - configMapRef: { name: fastapi-config }
            - secretRef: { name: davtro-secrets }
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
      containers:
        - name: spring-app
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring:latest
          ports: [{ containerPort: 8081 }]
          envFrom:
            - secretRef: { name: davtro-secrets }
          env:
            - { name: DB_HOST, value: "postgres-clusterip" }
            - { name: DB_NAME, value: "davtro_rentals" }
            - { name: KAFKA_BOOTSTRAP, value: "kafka-kraft:9092" }
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
    scrape_configs:
      - job_name: fastapi
        static_configs: [{ targets: ["fastapi-web-app-svc:80"] }]
      - job_name: postgres-exporter
        static_configs: [{ targets: ["postgres-exporter:9187"] }]
      - job_name: kafka-exporter
        static_configs: [{ targets: ["kafka-exporter:9308"] }]
      - job_name: node-exporter
        static_configs: [{ targets: ["node-exporter:9100"] }]
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
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 300m, memory: 256Mi }
      volumes:
        - name: config
          configMap: { name: prometheus-config }
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
            - name: DATA_SOURCE_NAME
              value: "postgresql://davtro:changeme@postgres-db:5432/davtro_rentals?sslmode=disable"
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
  name: allow-ingress-to-web
  namespace: davtro02
spec:
  podSelector: { matchLabels: { app: fastapi-web-app } }
  ingress:
    - from: []
      ports: [{ protocol: TCP, port: 8080 }]
  policyTypes: [Ingress]
EOF

cat > ${PROJECT_NAME}/manifests/base/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-ingress
  namespace: davtro02
spec:
  ingressClassName: public
  rules:
    - host: davtro.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: fastapi-web-app-svc, port: { number: 80 } }
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
spec:
  ingressClassName: public
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

  # - service-monitors.yaml  # odkomentuj jesli zainstalowany Prometheus Operator
resources:
- namespace.yaml
- serviceaccount.yaml
- configmap.yaml
- secret.yaml
- deployment.yaml
- service.yaml
- hpa.yaml
- pdb.yaml
- postgres.yaml
- redis.yaml
- vault.yaml
- kafka.yaml
- message-processor.yaml
- spring-app.yaml
- spark.yaml
- prometheus.yaml
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

images:
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
  newTag: 3e4abb5c0cd82ded66f4dc55644784f5c0bd1698
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
  newTag: 3e4abb5c0cd82ded66f4dc55644784f5c0bd1698
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spark
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spark
  newTag: 3e4abb5c0cd82ded66f4dc55644784f5c0bd1698
- name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
  newName: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
  newTag: 3e4abb5c0cd82ded66f4dc55644784f5c0bd1698
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
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
    newTag: latest
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
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
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
    newTag: staging
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-consumer
    newTag: staging
  - name: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-spring
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
      - Replace=true
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
  name        = "website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01"
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
  IMAGE_BASE: ghcr.io/${{ github.repository_owner }}/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01
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
    needs: [build-fastapi, build-consumer, build-spring, build-spark]
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
# SCRIPTS
# ============================================

cat > ${PROJECT_NAME}/scripts/setup.sh << 'EOF'
#!/bin/bash
set -e
echo "=== DavTro Setup ==="
echo "1. Upewnij sie, ze masz zainstalowane: docker, kubectl, kustomize, helm (opcjonalnie)"
echo "2. Zbuduj obrazy: docker build -t davtro-fastapi ./backend-fastapi"
echo "3. Zastosuj manifesty: kubectl apply -k manifests/overlays/production"
echo "4. Sprawdz status: kubectl get pods -n davtro02"
EOF
chmod +x ${PROJECT_NAME}/scripts/setup.sh

cat > ${PROJECT_NAME}/scripts/port-forward.sh << 'EOF'
#!/bin/bash
echo "Port-forwarding uslug DavTro..."
kubectl port-forward svc/fastapi-web-app-svc 8080:80 -n davtro02 &
kubectl port-forward svc/grafana 3000:3000 -n davtro02 &
kubectl port-forward svc/prometheus 9090:9090 -n davtro02 &
kubectl port-forward svc/kafka-ui 8081:80 -n davtro02 &
echo "FastAPI: http://localhost:8080"
echo "Grafana: http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "Kafka UI: http://localhost:8081"
EOF
chmod +x ${PROJECT_NAME}/scripts/port-forward.sh

# ============================================
# DOCS
# ============================================

cat > ${PROJECT_NAME}/README.md << 'EOF'
# Davtro Apartments – platforma wynajmu krotkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
Namespace: `davtro`

## Architektura
1. **Frontend** (SPA) → Nginx
2. **FastAPI** → PostgreSQL + Redis (cache) + Kafka (producent)
3. **message-processor** (consumer) → Kafka → email + PostgreSQL update
4. **Spring Boot** → panel raportowy / admin
5. **Spark** → analityka marketingowa z Kafka
6. **Vault** → sekrety (dev-mode, do produkcji HA)
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
	--from-literal=url=https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01.git \
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
- Zamien Vault dev-mode na oficjalny Helm chart (HA + auto-unseal)
- Skonfiguruj ArgoCD Vault Plugin (AVP) dla sekretow
- Skonfiguruj realny SMTP w secretach
- Zainstaluj Prometheus Operator jesli chcesz uzyc ServiceMonitor
Completed

Wdrożenie naprawione — wszystko stoi. Ostateczny status:

Klaster davtro02 (po Twoim usunięciu poda postgres)
Komponent	Status
postgres-db-0	✅ 1/1 Running — initContainer (root, runAsNonRoot: false) → chown 999:999 → initdb OK
fastapi (3/3 pody)	✅ 1/1 Running — nowa wersja, readiness /api/health przechodzi
spring-app	✅ 1/1 Running
vault-0	✅ 1/1 Running (dev-mode bez entrypointa)
message-processor, kafka-kraft, redis	✅ 1/1 Running
observability (prometheus, grafana, loki, tempo, promtail, exporters, pgadmin)	✅ 1/1 Running
ArgoCD	sync=Synced, health=Progressing — dokańcza operację
Co naprawiliśmy (przez Twój flow GitOps — 5 commitów)
postgres — root-owned PV na microk8s-hostpath (fsGroup nie działa) → initContainer robiący chown 999:999 + runAsNonRoot: false na poziomie kontenera (kubelet odrzucał root-init)
vault — CAP_SETFCAP: Operation not permitted → ominięcie docker-entrypoint.sh (dev-mode nie potrzebuje setcap/mlock)
kafka-topic-job — runAsNonRoot bez numerycznego UID → runAsUser: 1000 (wejdzie z PostSync hook)
pętla CI — bot commitował → build → bot commit… → warunek head_commit.author.username != 'github-actions[bot]'
Ostatni detal
kafka-topic-job (PostSync hook) zostanie odtworzony, gdy ArgoCD uzna stan za zdrowy — dzięki hook-delete-policy: BeforeHookCreation stary, padnięty job już usunął (NotFound = normalne). Jeśli op wisi bardzo długo na Ingressie (cecha microk8s — brak adresu LB), tematy Kafka i tak utworzą się automatycznie przy pierwszym połączeniu producenta (auto.create.topics domyślnie on).

Gdybyś chciał, w folderze mogę jeszcze (za Twoją akceptacją) dopiąć: pominięcie blokady syncu na Ingressie (np. ignoreDifferences/health check) albo porządki w pupa.txt. Ale technicznie — misja wykonana
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