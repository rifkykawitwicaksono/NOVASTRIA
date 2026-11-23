(()=> {
"use strict";
const SUPABASE_URL="https://tuwthcllamszebhizayk.supabase.co";
const SUPABASE_KEY="sb_publishable_SOt1_Iz0mSjIuX6FrddpjQ_h_cpHjpM";
const $=id=>document.getElementById(id);
let client=null, audio=null, soundOn=false, baseline=null, polling=false;
const sources=[
  {key:"orders",rpc:"admin_list_store_orders",label:"Pesanan baru",filter:r=>["pending_payment","pending_verification","processing"].includes(r.status)},
  {key:"payments",rpc:"admin_list_payments",label:"Pembayaran membership",filter:r=>r.status==="pending"||r.status==="verified"},
  {key:"deposits",rpc:"admin_list_wallet_deposits",label:"Pengajuan deposit",filter:r=>r.status==="pending"||r.status==="verified"},
  {key:"withdrawals",rpc:"admin_list_payout_requests",label:"Pengajuan pencairan",filter:r=>r.status==="pending"||r.status==="approved"}
];
function rowsOf(value){return Array.isArray(value)?value:[];}
function signature(row){return String(row.id||row.order_code||"")+":"+String(row.status||"");}
function makeSnapshot(data){const out={};for(const s of sources)out[s.key]=rowsOf(data[s.key]);return out;}
function titleFor(s,row,isNew){
 if(s.key==="orders")return "Pesanan baru"+(row.order_code?" — "+row.order_code:"");
 if(s.key==="payments")return isNew?"Pembayaran membership baru":"Status pembayaran membership berubah";
 if(s.key==="deposits")return isNew?"Pengajuan deposit baru":"Status deposit berubah";
 return isNew?"Pengajuan pencairan baru":"Status pengajuan pencairan berubah";
}
function notify(message){
 const el=$("adminSoundNotice");
 if(el){el.textContent=message;el.hidden=false;el.classList.add("visible");}
 if(soundOn)playAlert();
}
function playAlert(){
 try{
  const Ctx=window.AudioContext||window.webkitAudioContext;
  if(!Ctx)return;
  if(!audio)audio=new Ctx();
  if(audio.state==="suspended")audio.resume();
  const now=audio.currentTime;
  // Pola tiga nada tegas; volume sistem/perangkat mengatur tingkat suara akhir.
  [880,1175,988,1175].forEach((hz,i)=>{
   const start=now+i*.24,osc=audio.createOscillator(),gain=audio.createGain();
   osc.type="square";osc.frequency.setValueAtTime(hz,start);
   gain.gain.setValueAtTime(.0001,start);
   gain.gain.exponentialRampToValueAtTime(.72,start+.025);
   gain.gain.setValueAtTime(.72,start+.13);
   gain.gain.exponentialRampToValueAtTime(.0001,start+.2);
   osc.connect(gain);gain.connect(audio.destination);
   osc.start(start);osc.stop(start+.21);
  });
 }catch(e){console.warn("Audio notification unavailable",e);}
}
async function readAll(){
 const result=await Promise.all(sources.map(async s=>{
  const {data,error}=await client.rpc(s.rpc);
  if(error)throw error;
  return [s.key,rowsOf(data)];
 }));
 return Object.fromEntries(result);
}
function compare(next){
 if(!baseline){baseline=makeSnapshot(next);return;}
 for(const s of sources){
  const previous=new Map(baseline[s.key].map(r=>[String(r.id||r.order_code),String(r.status||"")]));
  for(const row of next[s.key]){
   const id=String(row.id||row.order_code||"");
   if(!id||!s.filter(row))continue;
   const oldStatus=previous.get(id);
   if(oldStatus===undefined){
    notify(titleFor(s,row,true));
   }else if(oldStatus!==String(row.status||"")){
    notify(titleFor(s,row,false));
   }
  }
 }
 baseline=makeSnapshot(next);
}
async function poll(){
 if(polling||!client)return;
 polling=true;
 try{const data=await readAll();compare(data);}
 catch(e){console.warn("Admin notification polling:",e.message);}
 finally{polling=false;}
}
async function boot(){
 const toggle=$("soundToggle"),test=$("soundTest");
 if(!toggle||!test||!window.supabase?.createClient)return;
 client=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
 toggle.addEventListener("click",async()=>{
  try{
   const Ctx=window.AudioContext||window.webkitAudioContext;
   if(!Ctx){toggle.textContent="Audio tidak didukung";return;}
   if(!audio)audio=new Ctx();
   await audio.resume();
   soundOn=!soundOn;
   toggle.textContent=soundOn?"Matikan suara":"Aktifkan suara";
   toggle.setAttribute("aria-pressed",String(soundOn));
   if(soundOn)playAlert();
  }catch(e){toggle.textContent="Aktifkan suara";console.warn(e);}
 });
 test.addEventListener("click",async()=>{
  try{const Ctx=window.AudioContext||window.webkitAudioContext;if(!audio&&Ctx)audio=new Ctx();if(audio)await audio.resume();playAlert();}
  catch(e){console.warn(e);}
 });
 // Tunggu sesi dan pemeriksaan admin pada halaman utama selesai.
 for(let i=0;i<20;i++){
  const {data}=await client.auth.getSession();
  if(data.session){
   const {data:allowed,error}=await client.rpc("is_novastria_admin");
   if(!error&&allowed===true){
    try{baseline=makeSnapshot(await readAll());}catch(e){console.warn(e);}
    setInterval(poll,15000);
   }
   return;
  }
  await new Promise(resolve=>setTimeout(resolve,500));
 }
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot,{once:true});else boot();
})();