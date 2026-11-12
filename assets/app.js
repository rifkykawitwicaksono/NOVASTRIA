const ADMIN_WA = "62895429626389";
const SUPABASE_URL = "https://hwtrqgtabamuixaqiscx.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_LBhpfEc_ANm5geSULymA6A_qINelIr6";
const money = n => new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(n);
const $ = id => document.getElementById(id);
const esc = v => String(v ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
let supabaseClient = null;
try {
  if (window.supabase && typeof window.supabase.createClient === "function") {
    supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
  }
} catch (error) {
  console.error("Supabase gagal diinisialisasi:", error);
}
let catalog=[],selectedOrder=null,joinType="referral",currentUser=null,member=null,memberLoadError="",authMode="login",activeCategory="all";

async function init(){
  $("year").textContent=new Date().getFullYear();
  $("contactLink").href="https://wa.me/"+ADMIN_WA+"?text="+encodeURIComponent("Halo admin NOVASTRIA, saya ingin bertanya.");
  try{
    let liveProducts=null;
    // Prioritaskan katalog Supabase agar perubahan admin langsung muncul di toko.
    if(supabaseClient){
      const live=await supabaseClient.from("store_products")
        .select("product,variant,public_price,reseller_price,in_stock")
        .eq("is_active",true).order("sort_order").order("product").order("variant");
      if(!live.error&&Array.isArray(live.data)&&live.data.length>0){
        liveProducts=live.data.map(p=>({
          product:p.product,variant:p.variant,inStock:p.in_stock,
          publicPrice:p.public_price,resellerPrice:p.reseller_price
        }));
      }else if(!live.error&&Array.isArray(live.data)&&live.data.length===0){
        console.warn("Katalog Supabase kosong; memakai katalog cadangan.");
      }else if(live.error){
        console.warn("Katalog Supabase belum tersedia; memakai katalog statis:",live.error.message);
      }
    }
    if(liveProducts){
      catalog=liveProducts;
    }else{
      const r=await fetch("assets/products.json");
      if(!r.ok)throw new Error("Katalog gagal dimuat.");
      catalog=(await r.json()).products||[];
    }
    $("productCount").textContent=catalog.length;
    populateCategories();renderProducts();
  }catch(error){$("productGrid").innerHTML='<div class="empty">Katalog belum bisa dimuat. Periksa koneksi dan sumber katalog.</div>';}
  $("searchInput").addEventListener("input",renderProducts);
  $("categoryTabs").addEventListener("click",event=>{const button=event.target.closest("[data-category]");if(!button)return;activeCategory=button.dataset.category;document.querySelectorAll(".category-tab").forEach(x=>x.classList.toggle("active",x===button));renderProducts();});
  $("openAccount").addEventListener("click",openAccount);
  $("manageAccount").addEventListener("click",openAccount);
  $("closeAccount").addEventListener("click",()=>$("accountDialog").close());
  $("authForm").addEventListener("submit",handleAuthSubmit);
  $("loginModeBtn").addEventListener("click",()=>setAuthMode("login"));
  $("signupModeBtn").addEventListener("click",()=>setAuthMode("signup"));
  $("accountDialog").addEventListener("click",event=>{if(event.target===$("accountDialog"))$("accountDialog").close();});
  setAuthMode("login");
  $("saveProfile").addEventListener("click",saveProfile);
  $("memberPayoutForm").addEventListener("submit",submitMemberPayout);
  $("walletDepositForm").addEventListener("submit",submitWalletDeposit);
  $("logout").addEventListener("click",logout);
  $("sendOrder").addEventListener("click",sendOrder);
  $("requestJoin").addEventListener("click",requestJoin);
  document.querySelectorAll("[data-close]").forEach(button=>button.addEventListener("click",()=>$(button.dataset.close).close()));
  document.querySelectorAll("[data-join]").forEach(button=>button.addEventListener("click",()=>openJoin(button.dataset.join)));
  // Katalog dan interaksi dasar tetap berjalan walau CDN/auth Supabase bermasalah.
  if (!supabaseClient) {
    setAuthMessage("Layanan akun belum termuat. Muat ulang halaman atau periksa koneksi internet.");
    updateMemberUI();
    return;
  }
  try {
    const result = await supabaseClient.auth.getSession();
    currentUser = result.data?.session?.user || null;
    await refreshMember();
    supabaseClient.auth.onAuthStateChange((_event, session) => {
      currentUser = session?.user || null;
      Promise.resolve().then(() => refreshMember());
    });
  } catch (error) {
    console.error("Inisialisasi sesi gagal:", error);
    updateMemberUI();
    setAuthMessage("Katalog tetap tersedia, tetapi layanan akun gagal terhubung. Coba muat ulang.");
  }
}

function productPlatform(name){
  const n=String(name||"").toLowerCase();
  if(n.includes("ios")&&n.includes("android"))return "Android & iOS";
  if(n.includes("ios")||n.includes("gbox")||n.includes("esign")||n==="migul")return "iOS";
  return "Android";
}

function productVisual(name){
  const n=String(name||"").toLowerCase();
  const icons=[["drip client apk","🌀"],["drip client root","🛠️"],["hg cheats","🎯"],["pato team","🛡️"],["prime hook","⚡"],["silent cheats","◉"],["certificate gbox","📜"],["migul","🍎"],["drip client wire","🔌"],["phantom","👻"],["xreg","✦"],["nexora","◈"]];
  return icons.find(([key])=>n.includes(key))?.[1]||"◆";
}
function productDescription(name){
  const n=String(name||"").toLowerCase();
  const descriptions=[["drip client root","Paket akses digital Android untuk perangkat dengan kebutuhan root. Periksa kompatibilitas perangkat."],["drip client apk","Paket akses digital Android. Pilih masa aktif yang sesuai sebelum memesan."],["hg cheats","Paket akses digital Android dengan pilihan masa aktif."],["pato team","Paket akses digital dengan pilihan varian Orange dan Blue."],["prime hook","Paket akses digital Android dengan beberapa pilihan masa aktif."],["silent cheats","Paket akses digital Android. Ketersediaan mengikuti stok tiap varian."],["certificate gbox","Layanan sertifikat untuk ekosistem iOS. Perhatikan masa berlaku dan ketentuan garansi."],["migul","Paket akses digital iOS dengan pilihan masa aktif."],["drip client wire","Paket akses digital untuk Android dan iOS. Pastikan kompatibilitas perangkat."],["phantom","Paket akses digital lintas platform dengan beberapa pilihan durasi."],["xreg","Paket akses digital lintas platform. Pilih durasi yang tersedia."],["nexora","Paket akses digital lintas platform dengan beberapa pilihan masa aktif."]];
  return descriptions.find(([key])=>n.includes(key))?.[1]||"Pilih varian yang tersedia dan periksa detail pesanan sebelum melanjutkan.";
}

function populateCategories(){
  const counts={Android:0,"iOS":0};
  const groups=new Map();
  catalog.forEach(p=>{if(!groups.has(p.product))groups.set(p.product,[]);groups.get(p.product).push(p);});
  for(const [name,items] of groups){
    const platform=productPlatform(name);
    if(platform==="Android & iOS"){counts.Android+=items.length;counts.iOS+=items.length;}
    else counts[platform]=(counts[platform]||0)+items.length;
  }
  document.querySelector('[data-category="Android"]').textContent="Android · "+counts.Android;
  document.querySelector('[data-category="iOS"]').textContent="iOS · "+counts.iOS;
}

function renderProducts(){
  const q=$("searchInput").value.toLowerCase().trim();
  const groups=new Map();
  catalog.forEach((p,index)=>{
    if(!groups.has(p.product))groups.set(p.product,[]);
    groups.get(p.product).push({...p,_index:index});
  });
  const visible=[...groups.entries()].map(([name,items])=>{
    const platform=productPlatform(name);
    const matches=items.filter(p=>!q||(p.product+" "+p.variant).toLowerCase().includes(q));
    return {name,platform,items:matches.length?matches:[],allItems:items};
  }).filter(g=>g.items.length&&(activeCategory==="all"||g.platform===activeCategory||g.platform==="Android & iOS"));
  $("catalogSummary").textContent=visible.length+" produk · "+visible.reduce((n,g)=>n+g.items.length,0)+" varian tersedia";
  if(!visible.length){$("productGrid").innerHTML='<div class="empty">Produk tidak ditemukan pada kategori ini.</div>';return;}
  $("productGrid").innerHTML=visible.map((g,groupIndex)=>{
    const available=g.items.filter(x=>x.inStock);
    const current=available[0]||g.items[0];
    const optionMarkup=g.items.map(p=>'<option value="'+p._index+'" '+(p._index===current._index?'selected':'')+' '+(!p.inStock?'data-unavailable="true"':'')+'>'+esc(p.variant)+(p.inStock?'':' — Stok habis')+'</option>').join("");
    const price=member?.resellerActive===true?current.resellerPrice:current.publicPrice;
    return '<article class="product-card grouped-product" data-product-card="'+groupIndex+'"><div class="product-card-top"><span class="platform-tag">'+esc(g.platform)+'</span><span class="variant-count">'+g.items.length+' varian</span></div><div class="product-visual"><span class="product-icon" aria-hidden="true">'+productVisual(g.name)+'</span><div class="product-visual-copy"><span>PRODUK DIGITAL</span><strong>'+(available.length?available.length+' varian tersedia':'Stok belum tersedia')+'</strong></div></div><h3>'+esc(g.name)+'</h3><p class="product-description">'+esc(productDescription(g.name))+'</p><label class="variant-picker-label">Pilih durasi / varian<select class="variant-picker" data-variant-picker="'+groupIndex+'">'+optionMarkup+'</select></label><div class="price-row"><div><div class="price-caption">'+(member?.resellerActive===true?"Harga reseller":"Harga publik")+'</div><div class="price-value" data-current-price>'+(!current.inStock?'Stok habis':price==null?'Harga belum ditetapkan':money(price))+'</div></div><span class="price-caption">IDR</span></div><button class="btn btn-primary" data-order="'+current._index+'" '+(!current.inStock?'disabled':'')+'>'+(current.inStock?'Pesan produk':'Stok tidak tersedia')+'</button></article>';
  }).join("");
  document.querySelectorAll("[data-variant-picker]").forEach(select=>select.addEventListener("change",()=>{
    const product=catalog[Number(select.value)],card=select.closest("[data-product-card]");
    const reseller=member?.resellerActive===true,price=reseller?product.resellerPrice:product.publicPrice;
    const button=card.querySelector("[data-order]"),priceNode=card.querySelector("[data-current-price]");
    button.dataset.order=String(Number(select.value));button.disabled=!product.inStock;
    button.textContent=product.inStock?"Pesan produk":"Stok tidak tersedia";
    priceNode.textContent=!product.inStock?"Stok habis":price==null?"Harga belum ditetapkan":money(price);
  }));
  document.querySelectorAll("[data-order]").forEach(b=>b.addEventListener("click",()=>openOrder(catalog[Number(b.dataset.order)])));
}

async function refreshMember(){
  member=null;
  memberLoadError="";
  if(!currentUser || !supabaseClient){
    updateMemberUI();
    return;
  }
  try{
    const profileResult=await supabaseClient.from("profiles").select("id,full_name,phone,referral_code").eq("id",currentUser.id).maybeSingle();
    if(profileResult.error) throw profileResult.error;
    if(!profileResult.data){
      throw new Error("Profil akun belum ditemukan. Pastikan trigger pembuatan profil pada SQL setup-auth.sql sudah dijalankan.");
    }
    const membershipResult=await supabaseClient.from("memberships").select("membership_type,status").eq("user_id",currentUser.id);
    if(membershipResult.error) throw membershipResult.error;
    const active=membershipResult.data||[];
    member={
      id:currentUser.id,email:currentUser.email,
      name:profileResult.data.full_name||currentUser.user_metadata?.full_name||"",
      phone:profileResult.data.phone||currentUser.user_metadata?.phone||"",
      referralCode:profileResult.data.referral_code||"",
      referralActive:active.some(m=>m.membership_type==="referral"&&m.status==="active"),
      resellerActive:active.some(m=>m.membership_type==="reseller"&&m.status==="active")
    };
    loadMemberPayoutHistory();
    loadMemberWallet();
  }catch(error){
    memberLoadError=error?.message||"Gagal mengambil data anggota dari database.";
    console.error("Gagal memuat data anggota:",error);
    setProfileMessage("Gagal memuat data anggota: "+memberLoadError);
  }finally{
    updateMemberUI();
  }
}

function updateMemberUI(){
  $("accountStatus").textContent=member
    ?(member.name||member.email)+" • Referral: "+(member.referralActive?"Aktif":"Belum aktif")+" • Reseller: "+(member.resellerActive?"Aktif":"Belum aktif")
    :(currentUser?(memberLoadError?"Data anggota gagal dimuat":"Memuat data anggota..."):"Belum masuk");
  $("authPanel").hidden=!!currentUser;
  $("profilePanel").hidden=!currentUser;
  if(member){
    $("memberStatus").innerHTML="<strong>"+esc(member.name||"Anggota NOVASTRIA")+"</strong><br>Email: "+esc(member.email||"-")+"<br>Referral: "+(member.referralActive?"Aktif":"Belum aktif")+"<br>Reseller: "+(member.resellerActive?"Aktif":"Belum aktif");
    $("memberName").value=member.name;
    $("memberPhone").value=member.phone;
    $("memberReferralCode").value=member.referralCode;
  }else if(currentUser){
    $("memberStatus").textContent=memberLoadError
      ?"Data anggota gagal dimuat: "+memberLoadError
      :"Memuat data profil anggota...";
  }else{
    $("memberStatus").textContent="Belum ada sesi akun aktif.";
  }
  renderProducts();
}


async function loadMemberPayoutHistory(){
 const box=$("memberPayoutHistory");if(!box||!currentUser)return;
 try{
  const r=await supabaseClient.rpc("member_list_commission_payout_requests");if(r.error)throw r.error;
  const labels={pending:"Menunggu",approved:"Disetujui",rejected:"Ditolak"};
  box.innerHTML="<strong>Riwayat pengajuan</strong><br>"+(r.data?.length?r.data.map(x=>esc(new Date(x.created_at).toLocaleDateString("id-ID"))+" — "+esc(money(x.amount))+" — "+esc(labels[x.status]||x.status)+(x.admin_notes?" ("+esc(x.admin_notes)+")":"")).join("<br>"):"Belum ada pengajuan.");
 }catch(e){box.textContent="Fitur ini aktif setelah migrasi database v3 dijalankan.";}
}
async function submitMemberPayout(e){
 e.preventDefault();if(!currentUser){setProfileMessage("Silakan login terlebih dahulu.");return;}
 const amount=Number($("memberPayoutAmount").value),method=$("memberPayoutMethod").value,account=$("memberPayoutAccount").value.trim(),notes=$("memberPayoutNotes").value.trim(),button=e.submitter;
 button.disabled=true;
 try{
  const r=await supabaseClient.rpc("member_request_commission_payout",{p_amount:amount,p_method:method,p_account:account,p_notes:notes||null});
  if(r.error)throw r.error;$("memberPayoutForm").reset();await loadMemberPayoutHistory();
  setProfileMessage("Pengajuan pencairan terkirim dan menunggu pemeriksaan admin.","success");
 }catch(err){setProfileMessage("Pengajuan gagal: "+err.message);}
 finally{button.disabled=false;}
}

async function loadPublicPaymentInstructions(){\n const box=$("walletPaymentInstructions");if(!box||!supabaseClient)return;\n try{const r=await supabaseClient.rpc("get_public_payment_instructions");if(r.error)throw r.error;const p=r.data||{};\n  if(!p.available){box.textContent="Pembayaran DANA belum diaktifkan admin. Hubungi admin sebelum melakukan transfer.";return;}\n  box.innerHTML="<strong>Transfer DANA</strong><br>Nomor: <strong>"+esc(p.account_number)+"</strong><br>Nama penerima: <strong>"+esc(p.account_name)+"</strong><br>"+esc(p.instructions)+"<br><small>Pastikan nama dan nomor penerima cocok sebelum transfer.</small>";\n }catch(e){box.textContent="Tujuan pembayaran belum dapat dimuat. Hubungi admin sebelum transfer.";console.warn("Payment instructions:",e.message);}\n}\n\nasync function loadMemberWallet(){
 const balance=$("walletBalance"),deposits=$("walletDepositHistory"),transactions=$("walletTransactionHistory");
 if(!currentUser||!supabaseClient)return;
 try{
  const r=await supabaseClient.rpc("member_get_wallet");if(r.error)throw r.error;
  const data=r.data||{};balance.textContent=money(Number(data.balance||0));
  const statuses={pending:"Menunggu verifikasi",verified:"Terverifikasi",rejected:"Ditolak"};
  deposits.innerHTML=(data.deposits||[]).length?(data.deposits||[]).map(d=>'<div class="wallet-history-item"><strong>'+esc(money(d.amount))+'</strong> · '+esc(d.payment_method)+' · '+esc(statuses[d.status]||d.status)+'<small>'+esc(new Date(d.created_at).toLocaleString("id-ID"))+(d.admin_notes?' · Catatan admin: '+esc(d.admin_notes):'')+'</small></div>').join(""):"Belum ada pengajuan deposit.";
  transactions.innerHTML=(data.transactions||[]).length?(data.transactions||[]).map(t=>'<div class="wallet-history-item"><strong class="'+(t.direction==="credit"?"wallet-credit":"wallet-debit")+'">'+(t.direction==="credit"?"+":"−")+esc(money(t.amount))+'</strong> · '+esc(t.description)+'<small>'+esc(new Date(t.created_at).toLocaleString("id-ID"))+'</small></div>').join(""):"Belum ada transaksi saldo.";
 }catch(e){
  balance.textContent="Belum tersedia";
  deposits.textContent="Fitur saldo menunggu migrasi database wallet-v1.sql.";
  transactions.textContent="Fitur saldo menunggu migrasi database wallet-v1.sql.";
  console.warn("Wallet belum tersedia:",e.message);
 }
}
async function submitWalletDeposit(e){
 e.preventDefault();if(!currentUser||!supabaseClient){setWalletMessage("Silakan login terlebih dahulu.");return;}
 const amount=Number($("walletDepositAmount").value),method=$("walletDepositMethod").value;
 const sender=$("walletSenderName").value.trim(),reference=$("walletPaymentReference").value.trim(),proof=$("walletProofUrl").value.trim();
 if(!Number.isSafeInteger(amount)||amount<10000){setWalletMessage("Minimal deposit Rp10.000.");return;}
 if(proof&&!/^https:\/\//i.test(proof)){setWalletMessage("Tautan bukti pembayaran harus menggunakan HTTPS.");return;}
 const button=e.submitter;button.disabled=true;button.textContent="Mengirim...";
 try{
  const r=await supabaseClient.rpc("member_create_wallet_deposit",{p_amount:amount,p_method:method,p_sender_name:sender,p_reference:reference||null,p_proof_url:proof||null});
  if(r.error)throw r.error;
  $("walletDepositForm").reset();await loadMemberWallet();
  setWalletMessage("Pengajuan deposit tercatat dan menunggu verifikasi admin. Saldo belum bertambah.","success");
 }catch(err){setWalletMessage("Pengajuan gagal: "+err.message);}
 finally{button.disabled=false;button.textContent="Kirim pengajuan deposit";}
}
function setWalletMessage(message,type="error"){$("walletMessage").textContent=message;$("walletMessage").className="auth-message "+type;}

function openAccount(){
  setAuthMessage("");setProfileMessage("");
  $("accountDialog").showModal();
}

function setAuthMode(mode){
  authMode=mode;
  const signup=mode==="signup";
  $("accountDialogTitle").textContent=signup?"Buat akun NOVASTRIA":"Masuk ke akun";
  $("authIntro").textContent=signup?"Buat akun dengan email aktif. Tautan verifikasi akan dikirim ke email Anda.":"Masuk untuk melihat profil dan status keanggotaan NOVASTRIA.";
  document.querySelectorAll(".signup-only").forEach(el=>el.hidden=!signup);
  $("authName").required=signup;
  $("authPhone").required=signup;
  $("authSubmit").textContent=signup?"Daftar akun":"Masuk";
  $("authPassword").autocomplete=signup?"new-password":"current-password";
  $("loginModeBtn").classList.toggle("active",!signup);
  $("signupModeBtn").classList.toggle("active",signup);
  $("loginModeBtn").setAttribute("aria-pressed",String(!signup));
  $("signupModeBtn").setAttribute("aria-pressed",String(signup));
  setAuthMessage("");
}

async function handleAuthSubmit(event){
  event.preventDefault();
  if (!supabaseClient) {
    setAuthMessage("Layanan akun belum termuat. Katalog tetap bisa digunakan; coba muat ulang halaman.");
    return;
  }
  const email=$("authEmail").value.trim(),password=$("authPassword").value,button=$("authSubmit");
  button.disabled=true;button.textContent=authMode==="signup"?"Mendaftarkan...":"Memeriksa...";
  setAuthMessage("");
  try{
    if(authMode==="signup"){
      const fullName=$("authName").value.trim(),phone=$("authPhone").value.trim(),inviteCode=$("authInviteCode").value.trim().toUpperCase();
      if(!fullName||!phone)throw new Error("Nama lengkap dan nomor WhatsApp wajib diisi.");
      const result=await supabaseClient.auth.signUp({
        email,password,
        options:{
          emailRedirectTo:window.location.origin+window.location.pathname,
          data:{full_name:fullName,phone:phone,referral_code:inviteCode||null}
        }
      });
      if(result.error)throw result.error;
      if(result.data.session){
        currentUser=result.data.user;
        await refreshMember();
        setProfileMessage("Akun berhasil dibuat dan sesi sudah aktif.","success");
      }else{
        $("authForm").reset();
        setAuthMessage("Pendaftaran diterima. Buka email Anda dan klik tautan verifikasi sebelum login.","success");
      }
    }else{
      const result=await supabaseClient.auth.signInWithPassword({email,password});
      if(result.error)throw result.error;
      currentUser=result.data.user;
      await refreshMember();
      setProfileMessage("Login berhasil.","success");
    }
  }catch(error){setAuthMessage(error.message||"Terjadi kesalahan. Coba kembali.");}
  finally{button.disabled=false;button.textContent=authMode==="signup"?"Daftar akun":"Masuk";}
}

async function saveProfile(){
  if(!currentUser || !supabaseClient)return;
  const full_name=$("memberName").value.trim(),phone=$("memberPhone").value.trim();
  if(!full_name||!phone){setProfileMessage("Nama dan nomor WhatsApp wajib diisi.");return;}
  const button=$("saveProfile");button.disabled=true;button.textContent="Menyimpan...";
  const result=await supabaseClient.from("profiles").update({full_name:full_name,phone:phone}).eq("id",currentUser.id);
  button.disabled=false;button.textContent="Simpan perubahan profil";
  if(result.error){setProfileMessage("Gagal menyimpan profil: "+result.error.message);return;}
  await refreshMember();setProfileMessage("Profil berhasil diperbarui.","success");
}

async function logout(){
  if (!supabaseClient) return;
  const result=await supabaseClient.auth.signOut();
  if(result.error){setProfileMessage("Gagal keluar: "+result.error.message);return;}
  currentUser=null;member=null;$("authForm").reset();$("accountDialog").close();updateMemberUI();
}

function openOrder(product){
  selectedOrder=product;
  const reseller=member?.resellerActive===true,price=reseller?product.resellerPrice:product.publicPrice;
  $("orderTitle").textContent=product.product;
  $("orderDescription").textContent=productDescription(product.product)+" Varian: "+product.variant+" — "+(price==null?"Harga perlu dikonfirmasi admin":money(price))+". Pesanan diteruskan ke admin melalui WhatsApp.";
  $("orderName").value=member?.name||"";$("orderPhone").value=member?.phone||"";
  $("orderDialog").showModal();
}

function sendOrder(){
  if(!selectedOrder)return;
  const name=$("orderName").value.trim(),phone=$("orderPhone").value.trim(),detail=$("orderDetail").value.trim();
  if(!name||!phone){alert("Isi nama dan nomor WhatsApp.");return;}
  const price=member?.resellerActive?selectedOrder.resellerPrice:selectedOrder.publicPrice;
  const msg="Halo admin NOVASTRIA, saya ingin memesan:\nProduk: "+selectedOrder.product+"\nVarian: "+selectedOrder.variant+"\nHarga: "+(price==null?"Konfirmasi admin":money(price))+"\nNama: "+name+"\nWhatsApp: "+phone+"\nDetail akun: "+(detail||"-");
  window.open("https://wa.me/"+ADMIN_WA+"?text="+encodeURIComponent(msg),"_blank");
}

function openJoin(type){
  if(!currentUser||!member){
    openAccount();setAuthMessage("Silakan masuk atau daftar akun terlebih dahulu untuk bergabung ke program anggota.");return;
  }
  joinType=type;
  const isReferral=type==="referral",fee=isReferral?150000:100000;
  $("joinTitle").textContent=isReferral?"Daftar Referral Member":"Daftar Reseller Member";
  $("joinSummary").innerHTML=isReferral
    ?"<strong>Biaya: "+money(fee)+"</strong><br>Referral member mendapat kode referral pribadi. Tidak otomatis menjadi reseller."
    :"<strong>Biaya: "+money(fee)+"</strong><br>Reseller mendapat akses harga khusus setelah pembayaran diverifikasi. Tidak otomatis menjadi referral member.";
  $("joinAccountNote").textContent="Akun: "+(member.name||member.email)+" • Kode referral pribadi: "+(member.referralCode||"Belum tersedia");
  $("joinDialog").showModal();
}

function requestJoin(){
  if(!member)return;
  const fee=joinType==="referral"?150000:100000,program=joinType==="referral"?"Referral Member":"Reseller Member";
  const msg="Halo admin NOVASTRIA, saya ingin mendaftar "+program+".\nNama: "+member.name+"\nEmail: "+member.email+"\nNomor WhatsApp: "+member.phone+"\nKode referral pribadi: "+member.referralCode+"\nBiaya: "+money(fee)+"\nMohon instruksi pembayaran dan verifikasi.";
  window.open("https://wa.me/"+ADMIN_WA+"?text="+encodeURIComponent(msg),"_blank");
}

function setAuthMessage(message,type="error"){$("authMessage").textContent=message;$("authMessage").className="auth-message "+type;}
function setProfileMessage(message,type="error"){$("profileMessage").textContent=message;$("profileMessage").className="auth-message "+type;}

init();