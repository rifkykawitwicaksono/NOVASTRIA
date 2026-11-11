(() => {
"use strict";
const SUPABASE_URL="https://hwtrqgtabamuixaqiscx.supabase.co";
const SUPABASE_PUBLISHABLE_KEY="sb_publishable_LBhpfEc_ANm5geSULymA6A_qINelIr6";
const $=id=>document.getElementById(id);
const client=window.supabase?.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
const params=new URLSearchParams(location.search);
function message(text,type="error"){const el=$("loginMessage");el.textContent=text;el.className="admin-login-message show "+type;}
function setBusy(busy){const button=$("adminLoginSubmit");button.disabled=busy;button.textContent=busy?"Memeriksa akun...":"Masuk ke Admin";}
async function verifyAdmin(){
 if(!client)return false;
 const {data,error}=await client.auth.getSession();
 if(error||!data.session)return false;
 const {data:allowed,error:checkError}=await client.rpc("is_novastria_admin");
 if(checkError)throw checkError;
 return allowed===true;
}
async function init(){
 $("togglePassword").addEventListener("click",()=>{const field=$("adminPassword"),show=field.type==="password";field.type=show?"text":"password";$("togglePassword").textContent=show?"Sembunyi":"Lihat";});
 if(!client){message("Layanan autentikasi tidak termuat. Periksa koneksi internet lalu muat ulang halaman.");return;}
 if(params.get("reason")==="not-admin")message("Akun sebelumnya bukan administrator. Masuk menggunakan akun admin NOVASTRIA.");
 try{if(await verifyAdmin()){location.replace("admin.html");return;}}catch(e){message("Gagal memeriksa hak admin: "+e.message+". Pastikan setup-admin.sql sudah dijalankan.");}
 $("adminLoginForm").addEventListener("submit",async event=>{
  event.preventDefault();setBusy(true);
  const email=$("adminEmail").value.trim().toLowerCase(),password=$("adminPassword").value;
  try{
   const session=await client.auth.getSession();
   if(session.data?.session){const out=await client.auth.signOut();if(out.error)throw out.error;}
   const {data,error}=await client.auth.signInWithPassword({email,password});
   if(error)throw error;
   const check=await client.rpc("is_novastria_admin");
   if(check.error)throw check.error;
   if(check.data!==true){await client.auth.signOut();throw new Error("Akun ini berhasil diautentikasi, tetapi belum memiliki hak admin. Periksa tabel novastria_admins di Supabase.");}
   message("Login admin berhasil. Membuka Admin Control Center...","success");
   location.replace("admin.html");
  }catch(e){message(e.message||"Login gagal. Periksa email dan password.");}
  finally{setBusy(false);}
 });
}
init();
})();