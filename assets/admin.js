const SUPABASE_URL = "https://hwtrqgtabamuixaqiscx.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_LBhpfEc_ANm5geSULymA6A_qINelIr6";
const $ = id => document.getElementById(id);
const db = window.supabase?.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
let rows = [];
function notice(message,type=""){ $("adminNotice").textContent=message; $("adminNotice").className="admin-alert "+type; }
async function start(){
  $("adminLogout").addEventListener("click",logout);
  $("reloadMembers").addEventListener("click",loadMembers);
  $("memberSearch").addEventListener("input",renderMembers);
  $("membershipFilter").addEventListener("change",renderMembers);
  if(!db){notice("Supabase tidak termuat. Periksa koneksi internet dan muat ulang.","error");return;}
  const {data:{session},error}=await db.auth.getSession();
  if(error||!session){notice("Silakan login terlebih dahulu melalui halaman toko.","error");$("adminIdentity").textContent="Belum login";return;}
  $("adminIdentity").textContent=session.user.email||"Akun terautentikasi";
  const check=await db.rpc("is_novastria_admin");
  if(check.error){notice("Gagal memeriksa hak admin: "+check.error.message+". Pastikan supabase/setup-admin.sql sudah dijalankan.","error");return;}
  if(check.data!==true){notice("Akses ditolak. Akun ini tidak terdaftar sebagai admin NOVASTRIA.","error");return;}
  $("adminPanel").hidden=false;
  notice("Akses admin terverifikasi. Data anggota dimuat dari database.","success");
  await loadMembers();
}
async function loadMembers(){
  $("membersBody").innerHTML='<tr><td colspan="6" class="admin-empty">Memuat data anggota...</td></tr>';
  const [profilesResult,membershipsResult]=await Promise.all([
    db.from("profiles").select("id,full_name,phone,referral_code"),
    db.from("memberships").select("user_id,membership_type,status")
  ]);
  if(profilesResult.error){notice("Gagal membaca profil: "+profilesResult.error.message,"error");return;}
  if(membershipsResult.error){notice("Gagal membaca keanggotaan: "+membershipsResult.error.message,"error");return;}
  const memberships=membershipsResult.data||[];
  rows=(profilesResult.data||[]).map(p=>({
    ...p,
    referral:memberships.find(m=>m.user_id===p.id&&m.membership_type==="referral")?.status||"none",
    reseller:memberships.find(m=>m.user_id===p.id&&m.membership_type==="reseller")?.status||"none"
  }));
  updateStats();renderMembers();
}
function updateStats(){
  $("totalMembers").textContent=rows.length;
  $("activeReferral").textContent=rows.filter(r=>r.referral==="active").length;
  $("activeReseller").textContent=rows.filter(r=>r.reseller==="active").length;
  $("inactiveMembership").textContent=rows.reduce((n,r)=>n+["referral","reseller"].filter(k=>r[k]==="inactive").length,0);
}
function renderMembers(){
  const q=$("memberSearch").value.trim().toLowerCase(),filter=$("membershipFilter").value;
  const visible=rows.filter(r=>{
    const hay=[r.full_name,r.phone,r.referral_code].join(" ").toLowerCase();
    const matchesFilter=!filter||r.referral===filter||r.reseller===filter;
    return hay.includes(q)&&matchesFilter;
  });
  if(!visible.length){$("membersBody").innerHTML='<tr><td colspan="6" class="admin-empty">Tidak ada anggota yang cocok.</td></tr>';return;}
  $("membersBody").innerHTML=visible.map(r=>'<tr><td><strong>'+escapeHtml(r.full_name||"Tanpa nama")+'</strong><small>'+escapeHtml(moneyDate(r.created_at))+'</small></td><td>'+escapeHtml(r.phone||"-")+'</td><td>'+escapeHtml(r.referral_code||"-")+'</td><td>'+statusText(r.referral)+'</td><td>'+statusText(r.reseller)+'</td><td><div class="admin-actions">'+actionButtons(r,"referral")+actionButtons(r,"reseller")+'</div></td></tr>').join("");
  $("membersBody").querySelectorAll("[data-status]").forEach(button=>button.addEventListener("click",()=>changeStatus(button.dataset.user,button.dataset.type,button.dataset.status)));
}
function statusText(s){return s==="active"?"Aktif":s==="inactive"?"Belum aktif":"Belum terdaftar";}
function actionButtons(r,type){
  const current=r[type],label=type==="referral"?"Referral":"Reseller";
  if(current==="none")return '<button disabled title="Membership belum dibuat">'+label+': belum ada</button>';
  const next=current==="active"?"inactive":"active",caption=next==="active"?"Aktifkan "+label:"Nonaktifkan "+label;
  return '<button data-user="'+r.id+'" data-type="'+type+'" data-status="'+next+'">'+caption+'</button>';
}
async function changeStatus(userId,type,status){
  const confirmation=status==="active"
    ?"Pastikan pembayaran program "+type+" sudah diverifikasi. Aktifkan sekarang?"
    :"Nonaktifkan status "+type+" anggota ini?";
  if(!confirm(confirmation))return;
  const {data,error}=await db.from("memberships").update({status}).eq("user_id",userId).eq("membership_type",type).select("user_id");
  if(error){notice("Perubahan gagal: "+error.message,"error");return;}
  if(!data?.length){notice("Tidak ada baris membership yang berubah. Membership mungkin belum dibuat.","error");return;}
  notice("Status "+type+" berhasil diperbarui.","success");
  await loadMembers();
}
function escapeHtml(value){return String(value??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));}
async function logout(){
  if(!db)return;
  const {error}=await db.auth.signOut();
  if(error){notice("Gagal keluar: "+error.message,"error");return;}
  window.location.href="index.html";
}
start();
