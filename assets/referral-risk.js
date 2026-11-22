(() => {
"use strict";
const SUPABASE_URL="https://tuwthcllamszebhizayk.supabase.co";
const SUPABASE_PUBLISHABLE_KEY="sb_publishable_SOt1_Iz0mSjIuX6FrddpjQ_h_cpHjpM";
const db=window.supabase?.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
const $=id=>document.getElementById(id);
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const date=v=>v?new Date(v).toLocaleString("id-ID",{dateStyle:"medium",timeStyle:"short"}):"-";
function status(message,type=""){const el=$("riskStatus");el.textContent=message;el.className="risk-status "+type;}
async function rpc(name,args={}){const r=await db.rpc(name,args);if(r.error)throw r.error;return r.data;}
async function load(){
 const body=$("riskRows");body.innerHTML='<tr><td colspan="7">Memuat data...</td></tr>';
 try{
  const rows=await rpc("admin_list_referral_risks");
  if(!rows?.length){body.innerHTML='<tr><td colspan="7">Belum ada sinyal risiko referral.</td></tr>';status("Pemeriksaan selesai. Tidak ada sinyal risiko yang tercatat.","success");return;}
  body.innerHTML=rows.map(r=>{
   const kind=r.signal_type==="shared_device_token"?"Token instalasi sama":"Nomor WhatsApp sama";
   const state=({open:"Menunggu tinjauan",cleared:"Dinyatakan aman",confirmed:"Dikonfirmasi"})[r.status]||r.status;
   const account='<strong>'+esc(r.full_name||"Tanpa nama")+'</strong><small>'+esc(r.email)+'</small><small>'+esc(r.phone||"-")+'</small>';
   const related=r.related_user_id?'<strong>'+esc(r.related_email||"Akun terkait")+'</strong><small>'+esc(r.related_user_id)+'</small>':"-";
   const actions=r.status==="open"?'<div class="risk-actions"><button data-id="'+r.id+'" data-decision="cleared">Tandai aman</button><button data-id="'+r.id+'" data-decision="confirmed">Konfirmasi fraud</button></div>':esc(r.review_note||"-");
   return '<tr><td>'+account+'</td><td>'+related+'</td><td>'+kind+'</td><td><span class="risk-pill '+esc(r.severity)+'">'+esc(r.severity.toUpperCase())+'</span></td><td>'+esc(state)+'</td><td>'+esc(date(r.created_at))+'</td><td>'+actions+'</td></tr>';
  }).join("");
  body.querySelectorAll("button[data-id]").forEach(button=>button.addEventListener("click",()=>review(button)));
  const open=rows.filter(r=>r.status==="open").length;
  status("Data dimuat: "+rows.length+" sinyal, "+open+" masih menunggu tinjauan.",open?"":"success");
 }catch(e){body.innerHTML='<tr><td colspan="7">Gagal memuat: '+esc(e.message)+'</td></tr>';status("Gagal memuat antrean. Pastikan supabase/anti-fraud-referral.sql sudah dijalankan. "+e.message,"error");}
}
async function review(button){
 const decision=button.dataset.decision;
 const note=prompt(decision==="confirmed"?"Catatan alasan konfirmasi fraud:":"Catatan pemeriksaan (opsional):","");
 if(note===null)return;
 if(decision==="confirmed"&&!note.trim()){alert("Catatan wajib diisi saat mengonfirmasi fraud.");return;}
 button.disabled=true;
 try{
  await rpc("admin_review_referral_risk",{p_signal_id:Number(button.dataset.id),p_decision:decision,p_note:note.trim()||null});
  status("Keputusan berhasil disimpan. Data diperbarui.","success");
  await load();
 }catch(e){status("Gagal menyimpan keputusan: "+e.message,"error");button.disabled=false;}
}
async function init(){
 if(!db){status("Supabase JS gagal dimuat. Periksa koneksi internet.","error");return;}
 try{
  const {data,error}=await db.auth.getSession();
  if(error||!data.session){location.replace("admin-login.html?next=referral-risk");return;}
  const allowed=await rpc("is_novastria_admin");
  if(allowed!==true){status("Akses ditolak. Halaman ini hanya untuk admin NOVASTRIA.","error");await db.auth.signOut();return;}
  status("Admin terverifikasi. Memuat antrean anti-fraud...");
  $("riskRefresh").addEventListener("click",load);
  await load();
 }catch(e){status("Tidak dapat memverifikasi admin: "+e.message,"error");}
}
init();
})();