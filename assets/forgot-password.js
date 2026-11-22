(() => {
"use strict";
const SUPABASE_URL="https://tuwthcllamszebhizayk.supabase.co";
const SUPABASE_PUBLISHABLE_KEY="sb_publishable_SOt1_Iz0mSjIuX6FrddpjQ_h_cpHjpM";
const $=id=>document.getElementById(id);
const isCustomer=new URLSearchParams(location.search).get("source")==="customer";
if(isCustomer){$("recoveryBack").href="index.html";$("recoveryBack").textContent="← Kembali ke toko";$("recoveryFoot").href="index.html";$("recoveryFoot").textContent="Kembali ke halaman masuk pelanggan";}
const client=window.supabase?.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
function message(text,type="error"){const el=$("forgotMessage");el.textContent=text;el.className="forgot-message show "+type;}
async function init(){
 if(!client){message("Layanan autentikasi tidak termuat. Muat ulang halaman.");return;}
 $("forgotForm").addEventListener("submit",async event=>{
  event.preventDefault();
  const email=$("forgotEmail").value.trim().toLowerCase();
  const button=$("forgotSubmit");button.disabled=true;button.textContent="Mengirim...";
  try{
   const redirectUrl=new URL("reset-password.html",location.href);if(isCustomer)redirectUrl.searchParams.set("source","customer");const redirectTo=redirectUrl.href;
   const {error}=await client.auth.resetPasswordForEmail(email,{redirectTo});
   if(error)throw error;
   message("Jika email tersebut terdaftar, tautan pemulihan telah diminta. Periksa kotak masuk dan folder spam.","success");
  }catch(error){
   message(error.message||"Permintaan gagal. Periksa email dan coba kembali.");
  }finally{
   button.disabled=false;button.textContent="Kirim tautan pemulihan";
  }
 });
}
init();
})();