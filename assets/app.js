const ADMIN_WA = "62895429626389";
const SUPABASE_URL = "https://hwtrqgtabamuixaqiscx.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_LBhpfEc_ANm5geSULymA6A_qINelIr6";
const money = n => new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(n);
const $ = id => document.getElementById(id);
const esc = v => String(v ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const supabase = window.supabase.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{
  auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
});
let catalog=[], selectedOrder=null, joinType="referral", currentUser=null, member=null, authMode="login";

async function init(){
  $("year").textContent=new Date().getFullYear();
  $("contactLink").href=\`https://wa.me/\${ADMIN_WA}?text=\${encodeURIComponent("Halo admin NOVASTRIA, saya ingin bertanya.")}\`;
  try{
    const r=await fetch("assets/products.json");
    if(!r.ok) throw new Error("Katalog gagal dimuat.");
    catalog=(await r.json()).products||[];
    $("productCount").textContent=catalog.length;
    populateCategories();renderProducts();
  }catch(error){$("productGrid").innerHTML='<div class="empty">Katalog belum bisa dimuat. Periksa file assets/products.json.</div>';}

  $("searchInput").addEventListener("input",renderProducts);
  $("categoryFilter").addEventListener("change",renderProducts);
  $("openAccount").addEventListener("click",openAccount);
  $("manageAccount").addEventListener("click",openAccount);
  $("closeAccount").addEventListener("click",()=>$("accountDialog").close());
  $("authForm").addEventListener("submit",handleAuthSubmit);
  $("toggleAuthMode").addEventListener("click",toggleAuthMode);
  $("saveProfile").addEventListener("click",saveProfile);
  $("logout").addEventListener("click",logout);
  $("sendOrder").addEventListener("click",sendOrder);
  $("requestJoin").addEventListener("click",requestJoin);
  document.querySelectorAll("[data-close]").forEach(button=>button.addEventListener("click",()=>$(button.dataset.close).close()));
  document.querySelectorAll("[data-join]").forEach(button=>button.addEventListener("click",()=>openJoin(button.dataset.join)));

  const {data:{session}}=await supabase.auth.getSession();
  currentUser=session?.user||null;
  await refreshMember();
  supabase.auth.onAuthStateChange((_event,session)=>{
    currentUser=session?.user||null;
    Promise.resolve().then(()=>refreshMember());
  });
}

function populateCategories(){
  const names=[...new Set(catalog.map(p=>p.product))].sort();
  $("categoryFilter").innerHTML='<option value="">Semua produk</option>'+names.map(n=>\`<option value="\${esc(n)}">\${esc(n)}</option>\`).join("");
}

function renderProducts(){
  const q=$("searchInput").value.toLowerCase().trim(),cat=$("categoryFilter").value;
  const filtered=catalog.filter(p=>(!cat||p.product===cat)&&(\`\${p.product} \${p.variant}\`.toLowerCase().includes(q)));
  if(!filtered.length){$("productGrid").innerHTML='<div class="empty">Produk tidak ditemukan.</div>';return;}
  $("productGrid").innerHTML=filtered.map(p=>{
    if(!p.inStock)return \`<article class="product-card"><h3>\${esc(p.product)}</h3><div class="variant">\${esc(p.variant)}</div><div class="out-stock">Stok tidak tersedia</div></article>\`;
    const reseller=member?.resellerActive===true,price=reseller?p.resellerPrice:p.publicPrice;
    return \`<article class="product-card"><h3>\${esc(p.product)}</h3><div class="variant">\${esc(p.variant)}</div><div class="price-row"><div><div class="price-caption">\${reseller?"Harga reseller":"Harga publik"}</div><div class="price-value">\${price==null?"Konfirmasi admin":money(price)}</div></div><span class="price-caption">IDR</span></div><button class="btn btn-primary" data-order="\${catalog.indexOf(p)}">Pesan produk</button></article>\`;
  }).join("");
  document.querySelectorAll("[data-order]").forEach(b=>b.addEventListener("click",()=>openOrder(catalog[Number(b.dataset.order)])));
}

async function refreshMember(){
  member=null;
  if(currentUser){
    const {data:profile,error:profileError}=await supabase.from("profiles").select("id,full_name,phone,referral_code").eq("id",currentUser.id).maybeSingle();
    const {data:memberships,error:membershipError}=await supabase.from("memberships").select("membership_type,status").eq("user_id",currentUser.id);
    if(profileError||membershipError){
      console.error("Gagal memuat data anggota:",profileError||membershipError);
      setProfileMessage("Akun berhasil masuk, tetapi data profil belum tersedia. Pastikan SQL setup-auth.sql sudah dijalankan di Supabase.");
    }else if(profile){
      const active=memberships||[];
      member={
        id:currentUser.id,email:currentUser.email,
        name:profile.full_name||currentUser.user_metadata?.full_name||"",
        phone:profile.phone||currentUser.user_metadata?.phone||"",
        referralCode:profile.referral_code||"",
        referralActive:active.some(m=>m.membership_type==="referral"&&m.status==="active"),
        resellerActive:active.some(m=>m.membership_type==="reseller"&&m.status==="active")
      };
    }else{
      setProfileMessage("Profil akun belum ditemukan. Jalankan SQL setup-auth.sql di Supabase, lalu keluar dan masuk kembali.");
    }
  }
  updateMemberUI();
}

function updateMemberUI(){
  $("accountStatus").textContent=member
    ?\`\${member.name||member.email} • Referral: \${member.referralActive?"Aktif":"Belum aktif"} • Reseller: \${member.resellerActive?"Aktif":"Belum aktif"}\`
    :currentUser?"Memuat data anggota...":"Belum masuk";
  $("authPanel").hidden=!!currentUser;
  $("profilePanel").hidden=!currentUser;
  if(member){
    $("memberStatus").innerHTML=\`<strong>\${esc(member.name||"Anggota NOVASTRIA")}</strong><br>Email: \${esc(member.email||"-")}<br>Referral: \${member.referralActive?"Aktif":"Belum aktif"}<br>Reseller: \${member.resellerActive?"Aktif":"Belum aktif"}\`;
    $("memberName").value=member.name;
    $("memberPhone").value=member.phone;
    $("memberReferralCode").value=member.referralCode;
  }else if(currentUser){
    $("memberStatus").textContent="Data profil belum tersedia. Pastikan migrasi database sudah dijalankan.";
  }else{
    $("memberStatus").textContent="Belum ada sesi akun aktif.";
  }
  renderProducts();
}

function openAccount(){
  setAuthMessage("");
  setProfileMessage("");
  $("accountDialog").showModal();
}

function toggleAuthMode(){
  authMode=authMode==="login"?"signup":"login";
  const signup=authMode==="signup";
  $("accountDialogTitle").textContent=signup?"Buat akun NOVASTRIA":"Masuk ke akun";
  $("authIntro").textContent=signup?"Buat akun dengan email aktif. Tautan verifikasi akan dikirim ke email Anda.":"Masuk untuk melihat profil dan status keanggotaan NOVASTRIA.";
  document.querySelectorAll(".signup-only").forEach(el=>el.hidden=!signup);
  $("authName").required=signup;
  $("authPhone").required=signup;
  $("authSubmit").textContent=signup?"Daftar akun":"Masuk";
  $("toggleAuthMode").textContent=signup?"Sudah punya akun? Masuk":"Belum punya akun? Daftar sekarang";
  $("authPassword").autocomplete=signup?"new-password":"current-password";
  setAuthMessage("");
}

async function handleAuthSubmit(event){
  event.preventDefault();
  const email=$("authEmail").value.trim();
  const password=$("authPassword").value;
  const button=$("authSubmit");
  button.disabled=true;button.textContent=authMode==="signup"?"Mendaftarkan...":"Memeriksa...";
  setAuthMessage("");
  try{
    if(authMode==="signup"){
      const fullName=$("authName").value.trim();
      const phone=$("authPhone").value.trim();
      const inviteCode=$("authInviteCode").value.trim().toUpperCase();
      if(!fullName||!phone)throw new Error("Nama lengkap dan nomor WhatsApp wajib diisi.");
      const {data,error}=await supabase.auth.signUp({
        email,password,
        options:{
          emailRedirectTo:window.location.origin+window.location.pathname,
          data:{full_name:fullName,phone,referral_code:inviteCode||null}
        }
      });
      if(error)throw error;
      if(data.session){
        currentUser=data.user;
        await refreshMember();
        setAuthMessage("Akun berhasil dibuat dan sesi sudah aktif.","success");
      }else{
        $("authForm").reset();
        setAuthMessage("Pendaftaran diterima. Buka email Anda dan klik tautan verifikasi sebelum login.","success");
      }
    }else{
      const {data,error}=await supabase.auth.signInWithPassword({email,password});
      if(error)throw error;
      currentUser=data.user;
      await refreshMember();
      setAuthMessage("Login berhasil.","success");
    }
  }catch(error){
    setAuthMessage(error.message||"Terjadi kesalahan. Coba kembali.");
  }finally{
    button.disabled=false;
    button.textContent=authMode==="signup"?"Daftar akun":"Masuk";
  }
}

async function saveProfile(){
  if(!currentUser)return;
  const full_name=$("memberName").value.trim();
  const phone=$("memberPhone").value.trim();
  if(!full_name||!phone){setProfileMessage("Nama dan nomor WhatsApp wajib diisi.");return;}
  const button=$("saveProfile");button.disabled=true;button.textContent="Menyimpan...";
  const {error}=await supabase.from("profiles").update({full_name,phone}).eq("id",currentUser.id);
  button.disabled=false;button.textContent="Simpan perubahan profil";
  if(error){setProfileMessage("Gagal menyimpan profil: "+error.message);return;}
  await refreshMember();
  setProfileMessage("Profil berhasil diperbarui.","success");
}

async function logout(){
  const {error}=await supabase.auth.signOut();
  if(error){setProfileMessage("Gagal keluar: "+error.message);return;}
  currentUser=null;member=null;
  $("authForm").reset();
  $("accountDialog").close();
  updateMemberUI();
}

function openOrder(product){
  selectedOrder=product;
  const reseller=member?.resellerActive===true;
  const price=reseller?product.resellerPrice:product.publicPrice;
  $("orderTitle").textContent=product.product;
  $("orderDescription").textContent=\`\${product.variant} — \${price==null?"Harga perlu dikonfirmasi admin":money(price)}. Pesanan diteruskan ke admin melalui WhatsApp.\`;
  $("orderName").value=member?.name||"";
  $("orderPhone").value=member?.phone||"";
  $("orderDialog").showModal();
}

function sendOrder(){
  if(!selectedOrder)return;
  const name=$("orderName").value.trim(),phone=$("orderPhone").value.trim(),detail=$("orderDetail").value.trim();
  if(!name||!phone){alert("Isi nama dan nomor WhatsApp.");return;}
  const price=member?.resellerActive?selectedOrder.resellerPrice:selectedOrder.publicPrice;
  const msg=\`Halo admin NOVASTRIA, saya ingin memesan:\\nProduk: \${selectedOrder.product}\\nVarian: \${selectedOrder.variant}\\nHarga: \${price==null?"Konfirmasi admin":money(price)}\\nNama: \${name}\\nWhatsApp: \${phone}\\nDetail akun: \${detail||"-"}\`;
  window.open(\`https://wa.me/\${ADMIN_WA}?text=\${encodeURIComponent(msg)}\`,"_blank");
}

function openJoin(type){
  if(!currentUser||!member){
    openAccount();
    setAuthMessage("Silakan masuk atau daftar akun terlebih dahulu untuk bergabung ke program anggota.");
    return;
  }
  joinType=type;
  const isReferral=type==="referral";
  const fee=isReferral?150000:100000;
  $("joinTitle").textContent=isReferral?"Daftar Referral Member":"Daftar Reseller Member";
  $("joinSummary").innerHTML=isReferral
    ?\`<strong>Biaya: \${money(fee)}</strong><br>Referral member mendapat kode referral pribadi. Tidak otomatis menjadi reseller.\`
    :\`<strong>Biaya: \${money(fee)}</strong><br>Reseller mendapat akses harga khusus setelah pembayaran diverifikasi. Tidak otomatis menjadi referral member.\`;
  $("joinAccountNote").textContent=\`Akun: \${member.name||member.email} • Kode referral pribadi: \${member.referralCode||"Belum tersedia"}\`;
  $("joinDialog").showModal();
}

function requestJoin(){
  if(!member)return;
  const fee=joinType==="referral"?150000:100000;
  const program=joinType==="referral"?"Referral Member":"Reseller Member";
  const msg=\`Halo admin NOVASTRIA, saya ingin mendaftar \${program}.\\nNama: \${member.name}\\nEmail: \${member.email}\\nNomor WhatsApp: \${member.phone}\\nKode referral pribadi: \${member.referralCode}\\nBiaya: \${money(fee)}\\nMohon instruksi pembayaran dan verifikasi.\`;
  window.open(\`https://wa.me/\${ADMIN_WA}?text=\${encodeURIComponent(msg)}\`,"_blank");
}

function setAuthMessage(message,type="error"){$("authMessage").textContent=message;$("authMessage").className="auth-message "+type;}
function setProfileMessage(message,type="error"){$("profileMessage").textContent=message;$("profileMessage").className="auth-message "+type;}

init();