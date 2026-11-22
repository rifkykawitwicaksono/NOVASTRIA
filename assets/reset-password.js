(() => {
"use strict";
const SUPABASE_URL="https://tuwthcllamszebhizayk.supabase.co";
const SUPABASE_PUBLISHABLE_KEY="sb_publishable_SOt1_Iz0mSjIuX6FrddpjQ_h_cpHjpM";
const $=id=>document.getElementById(id);
const client=window.supabase?.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{
 auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
});
let recoverySessionReady=false;
function message(text,type="error"){
 const el=$("resetMessage");el.textContent=text;el.className="reset-message show "+type;
}
function showForm(){recoverySessionReady=true;$("resetForm").hidden=false;}
async function init(){
 if(!client){message("Layanan autentikasi tidak termuat. Muat ulang halaman.");return;}
 const params=new URLSearchParams(location.search);
 const hash=new URLSearchParams(location.hash.replace(/^#/,""));
 if(params.get("error")||hash.get("error")){
  message("Tautan pemulihan tidak valid atau sudah kedaluwarsa. Minta tautan baru dari halaman login admin.");
  return;
 }
 client.auth.onAuthStateChange((event,session)=>{
  if(event==="PASSWORD_RECOVERY"&&session){showForm();message("Tautan valid. Silakan buat password baru.","success");}
 });
 const {data,error}=await client.auth.getSession();
 if(error){message("Sesi pemulihan gagal dibaca: "+error.message);return;}
 if(data.session){
  showForm();
  message("Sesi pemulihan terdeteksi. Silakan buat password baru.","success");
 }else{
  message("Buka halaman ini melalui tautan pemulihan yang dikirim ke email Anda. Jika tautan sudah kedaluwarsa, minta tautan baru.");
 }
 $("resetForm").addEventListener("submit",async event=>{
  event.preventDefault();
  if(!recoverySessionReady){message("Sesi pemulihan belum valid. Minta tautan baru.");return;}
  const password=$("newPassword").value,confirm=$("confirmPassword").value;
  if(password.length<8){message("Password minimal 8 karakter.");return;}
  if(password!==confirm){message("Konfirmasi password tidak sama.");return;}
  const button=$("resetSubmit");button.disabled=true;button.textContent="Menyimpan...";
  try{
   const {error:updateError}=await client.auth.updateUser({password});
   if(updateError)throw updateError;
   await client.auth.signOut();
   $("resetForm").hidden=true;
   message("Password berhasil diperbarui. Silakan masuk kembali menggunakan password baru.","success");
  }catch(error){
   message(error.message||"Password gagal diperbarui. Minta tautan pemulihan baru jika diperlukan.");
  }finally{
   button.disabled=false;button.textContent="Simpan password baru";
  }
 });
}
init();
})();