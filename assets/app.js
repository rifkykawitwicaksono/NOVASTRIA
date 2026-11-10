const ADMIN_WA = "62895429626389";
const money = n => new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(n);
let catalog=[], selectedOrder=null, joinType="referral";
let member=JSON.parse(localStorage.getItem("novastria_demo_member")||"null");
const $=id=>document.getElementById(id);
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
async function init(){
 $("year").textContent=new Date().getFullYear();
 $("contactLink").href=`https://wa.me/${ADMIN_WA}?text=${encodeURIComponent("Halo admin NOVASTRIA, saya ingin bertanya.")}`;
 try{const r=await fetch("assets/products.json");if(!r.ok)throw Error();catalog=(await r.json()).products||[];$("productCount").textContent=catalog.length;populateCategories();renderProducts();}
 catch{$("productGrid").innerHTML='<div class="empty">Katalog belum bisa dimuat. Periksa file assets/products.json.</div>';}
 updateMemberUI();
}
function populateCategories(){const names=[...new Set(catalog.map(p=>p.product))].sort();$("categoryFilter").innerHTML='<option value="">Semua produk</option>'+names.map(n=>`<option value="${esc(n)}">${esc(n)}</option>`).join("");}
function renderProducts(){
 const q=$("searchInput").value.toLowerCase().trim(),cat=$("categoryFilter").value;
 const filtered=catalog.filter(p=>(!cat||p.product===cat)&&(`${p.product} ${p.variant}`.toLowerCase().includes(q)));
 if(!filtered.length){$("productGrid").innerHTML='<div class="empty">Produk tidak ditemukan.</div>';return;}
 $("productGrid").innerHTML=filtered.map(p=>{if(!p.inStock)return `<article class="product-card"><h3>${esc(p.product)}</h3><div class="variant">${esc(p.variant)}</div><div class="out-stock">Stok tidak tersedia</div></article>`;const reseller=member?.resellerActive===true,price=reseller?p.resellerPrice:p.publicPrice;return `<article class="product-card"><h3>${esc(p.product)}</h3><div class="variant">${esc(p.variant)}</div><div class="price-row"><div><div class="price-caption">${reseller?"Harga reseller":"Harga publik"}</div><div class="price-value">${(price==null)?"Konfirmasi admin":money(price)}</div></div><span class="price-caption">IDR</span></div><button class="btn btn-primary" data-order="${catalog.indexOf(p)}">Pesan produk</button></article>`;}).join("");
 document.querySelectorAll("[data-order]").forEach(b=>b.addEventListener("click",()=>openOrder(catalog[Number(b.dataset.order)])));
}
function openOrder(p){selectedOrder=p;$("orderTitle").textContent=p.product;$("orderDescription").textContent=`${p.variant} — ${(member?.resellerActive?p.resellerPrice:p.publicPrice)==null?"Harga perlu dikonfirmasi admin":money(member?.resellerActive?p.resellerPrice:p.publicPrice)}. Pesanan diteruskan ke admin melalui WhatsApp.`;$("orderName").value=member?.name||"";$("orderPhone").value=member?.phone||"";$("orderDialog").showModal();}
$("sendOrder").addEventListener("click",()=>{if(!selectedOrder)return;const name=$("orderName").value.trim(),phone=$("orderPhone").value.trim(),detail=$("orderDetail").value.trim();if(!name||!phone){alert("Isi nama dan nomor WhatsApp.");return;}const price=member?.resellerActive?selectedOrder.resellerPrice:selectedOrder.publicPrice;const msg=`Halo admin NOVASTRIA, saya ingin memesan:\nProduk: ${selectedOrder.product}\nVarian: ${selectedOrder.variant}\nHarga: ${price==null?"Konfirmasi admin":money(price)}\nNama: ${name}\nWhatsApp: ${phone}\nDetail akun: ${detail||"-"}`;window.open(`https://wa.me/${ADMIN_WA}?text=${encodeURIComponent(msg)}`,"_blank");});
$("searchInput").addEventListener("input",renderProducts);$("categoryFilter").addEventListener("change",renderProducts);
function updateMemberUI(){
 $("accountStatus").textContent=member?`${member.name||"Anggota"} • Referral: ${member.referralActive?"Aktif":"Tidak aktif"} • Reseller: ${member.resellerActive?"Aktif":"Tidak aktif"}`:"Belum masuk";
 $("memberStatus").textContent=member?`Nama: ${member.name||"-"} | Referral: ${member.referralActive?"Aktif":"Tidak aktif"} | Reseller: ${member.resellerActive?"Aktif":"Tidak aktif"} | Kode: ${member.referralCode||"Belum dibuat"}`:"Belum ada status keanggotaan aktif.";
 $("memberName").value=member?.name||"";$("memberPhone").value=member?.phone||"";$("refCode").value=member?.referralCode||"";
 $("memberNotice").textContent=member?.resellerActive?"Harga reseller ditampilkan. Status browser ini hanya simulasi, bukan bukti pembayaran.":"Harga publik ditampilkan. Masuk sebagai reseller untuk melihat harga reseller.";renderProducts();
}
function openAccount(){$("accountDialog").showModal();}
$("openAccount").addEventListener("click",openAccount);$("manageAccount").addEventListener("click",openAccount);
$("saveProfile").addEventListener("click",()=>{const name=$("memberName").value.trim(),phone=$("memberPhone").value.trim();if(!name||!phone){alert("Isi nama dan nomor WhatsApp.");return;}member={...(member||{}),name,phone,referralCode:member?.referralCode||"",referralActive:member?.referralActive||false,resellerActive:member?.resellerActive||false};localStorage.setItem("novastria_demo_member",JSON.stringify(member));updateMemberUI();alert("Profil demo tersimpan di browser ini.");});
$("logout").addEventListener("click",()=>{if(!confirm("Reset data demo akun di browser ini?"))return;member=null;localStorage.removeItem("novastria_demo_member");updateMemberUI();});
document.querySelectorAll("[data-join]").forEach(b=>b.addEventListener("click",()=>openJoin(b.dataset.join)));
function openJoin(type){joinType=type;const ref=type==="referral";$("joinTitle").textContent=ref?"Daftar Referral Member":"Daftar Reseller Member";$("joinSummary").innerHTML=ref?`<strong>Biaya: ${money(150000)}</strong><br>Referral member mendapat kode referral. Tidak otomatis menjadi reseller.`:`<strong>Biaya: ${money(100000)}</strong><br>Reseller mendapat akses harga khusus setelah pembayaran diverifikasi. Tidak otomatis menjadi referral member.`;$("joinName").value=member?.name||"";$("joinPhone").value=member?.phone||"";$("joinRef").value="";$("joinDialog").showModal();}
$("requestJoin").addEventListener("click",()=>{const name=$("joinName").value.trim(),phone=$("joinPhone").value.trim(),ref=$("joinRef").value.trim();if(!name||!phone){alert("Isi nama dan nomor WhatsApp.");return;}const fee=joinType==="referral"?150000:100000,program=joinType==="referral"?"Referral Member":"Reseller Member";const msg=`Halo admin NOVASTRIA, saya ingin mendaftar ${program}.\nNama: ${name}\nNomor WhatsApp: ${phone}\nKode referral pengundang: ${ref||"-"}\nBiaya: ${money(fee)}\nMohon instruksi pembayaran dan verifikasi.`;window.open(`https://wa.me/${ADMIN_WA}?text=${encodeURIComponent(msg)}`,"_blank");});
init();