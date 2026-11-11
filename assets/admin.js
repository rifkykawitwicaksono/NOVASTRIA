const SUPABASE_URL="https://hwtrqgtabamuixaqiscx.supabase.co";
const SUPABASE_PUBLISHABLE_KEY="sb_publishable_LBhpfEc_ANm5geSULymA6A_qINelIr6";
const $=id=>document.getElementById(id);
const money=n=>new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(Number(n||0));
const priceLabel=n=>n===null||n===undefined?"Belum ditetapkan":money(n);
const date=v=>v?new Date(v).toLocaleString("id-ID",{dateStyle:"medium",timeStyle:"short"}):"-";
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const db=window.supabase?.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
let members=[],payments=[],commissions=[],payouts=[],products=[],overview={},sales=[],payoutRequests=[],salesSummary={};
function notice(message,type=""){const el=$("adminNotice");el.textContent=message;el.className="admin-alert "+type;}
function badge(status){return '<span class="admin-badge '+esc(status)+'">'+esc(({active:"Aktif",inactive:"Nonaktif",none:"Belum ada",pending:"Menunggu",verified:"Terverifikasi",rejected:"Ditolak",approved:"Disetujui",paid:"Dibayar"}[status]||status))+'</span>';}
async function rpc(name,args={}){const r=await db.rpc(name,args);if(r.error)throw r.error;return r.data;}
async function start(){
  $("adminLogout").addEventListener("click",logout);
  $("refreshAll").addEventListener("click",loadAll);
  document.querySelectorAll("[data-tab]").forEach(b=>b.addEventListener("click",()=>showTab(b.dataset.tab)));
  $("memberSearch").addEventListener("input",renderMembers);$("memberFilter").addEventListener("change",renderMembers);
  $("paymentFilter").addEventListener("change",renderPayments);$("paymentSearch").addEventListener("input",renderPayments);
  $("productSearch").addEventListener("input",renderProducts);$("productVisibility").addEventListener("change",renderProducts);
  $("paymentType").addEventListener("change",()=>{$("paymentAmount").value=$("paymentType").value==="referral"?150000:100000;});
  $("paymentForm").addEventListener("submit",createPayment);
  $("payoutForm").addEventListener("submit",createPayout);
  $("productForm").addEventListener("submit",saveProduct);
  $("saleForm").addEventListener("submit",createSale);
  $("resetProduct").addEventListener("click",resetProductForm);
  if(!db){notice("Supabase JS tidak termuat. Periksa koneksi internet lalu muat ulang.","error");return;}
  const {data,error}=await db.auth.getSession();
  if(error||!data.session){location.replace("admin-login.html?next=admin");return;}
  $("adminIdentity").textContent="Login sebagai "+(data.session.user.email||"akun terautentikasi");
  try{
    const allowed=await rpc("is_novastria_admin");
    if(allowed!==true){notice("Akses ditolak. Akun ini tidak memiliki hak Admin NOVASTRIA. Silakan gunakan akun admin.","error");$("adminIdentity").textContent="Akun bukan admin";setTimeout(()=>location.replace("admin-login.html?reason=not-admin"),1200);return;}
    $("adminPanel").hidden=false;notice("Hak admin terverifikasi. Memuat modul operasional...","success");
    await loadAll();
  }catch(e){notice("Gagal memeriksa hak admin / memuat sistem: "+e.message+". Pastikan setup-admin.sql dan admin-controller-v2.sql sudah dijalankan.","error");}
}
function showTab(name){
  document.querySelectorAll("[data-tab]").forEach(b=>b.classList.toggle("active",b.dataset.tab===name));
  document.querySelectorAll(".admin-section").forEach(s=>s.hidden=s.id!=="tab-"+name);
}
async function loadAll(){
  notice("Memperbarui data admin...");
  const tasks=[
    ["members","admin_list_members"],["overview","admin_get_overview"],["payments","admin_list_payments"],
    ["commissions","admin_list_commissions"],["payouts","admin_list_payouts"],["products","admin_list_products"],["sales","admin_list_sales"],["salesSummary","admin_get_sales_summary"],["payoutRequests","admin_list_payout_requests"],["audit","admin_list_audit"]
  ];
  const results=await Promise.all(tasks.map(async ([key,fn])=>{try{return [key,await rpc(fn)];}catch(e){return [key,{__error:e.message}];}}));
  const errors=[];
  for(const [key,value] of results){
    if(value&&value.__error){errors.push(key+": "+value.__error);continue;}
    if(key==="overview")overview=value||{};
    else if(key==="members")members=value||[];
    else if(key==="payments")payments=value||[];
    else if(key==="commissions")commissions=value||[];
    else if(key==="payouts")payouts=value||[];
    else if(key==="products")products=value||[];
    else if(key==="sales")sales=value||[];
    else if(key==="salesSummary")salesSummary=value||{};
    else if(key==="payoutRequests")payoutRequests=value||[];
    else if(key==="audit")renderAudit(value||[]);
  }
  renderAll();
  if(errors.length)notice("Sebagian modul gagal dimuat: "+errors.join(" | "), "error");
  else notice("Semua modul berhasil diperbarui dari Supabase.","success");
}
function renderAll(){renderStats();renderMembers();renderMemberOptions();renderPayments();renderCommissions();renderPayouts();renderProducts();renderSales();renderPayoutRequests();renderReports();}
function renderStats(){
  $("statMembers").textContent=overview.members??members.length;
  $("statReferral").textContent=overview.referral_active??members.filter(m=>m.referral_status==="active").length;
  $("statReseller").textContent=overview.reseller_active??members.filter(m=>m.reseller_status==="active").length;
  $("statPending").textContent=overview.pending_payments??payments.filter(p=>p.status==="pending").length;
  $("statRevenue").textContent=money(overview.verified_revenue);
  $("statCommission").textContent=money(overview.available_commission);
  $("statPayout").textContent=money(overview.paid_commission);
  $("statProducts").textContent=products.filter(p=>p.is_active).length;
  $("dashboardSummary").textContent="Saat ini terdapat "+members.length+" profil anggota, "+payments.filter(p=>p.status==="pending").length+" pembayaran menunggu verifikasi, "+commissions.length+" catatan komisi referral, dan "+products.length+" produk katalog. Periksa bukti pembayaran sebelum melakukan verifikasi.";
}
function renderMembers(){
  const q=$("memberSearch").value.trim().toLowerCase(),filter=$("memberFilter").value;
  const list=members.filter(m=>{
    const text=[m.full_name,m.email,m.phone,m.referral_code].join(" ").toLowerCase();
    const ok=filter==="referral"?m.referral_status==="active":filter==="reseller"?m.reseller_status==="active":filter==="none"?m.referral_status==="none"&&m.reseller_status==="none":true;
    return text.includes(q)&&ok;
  });
  $("membersBody").innerHTML=list.length?list.map(m=>'<tr><td><strong>'+esc(m.full_name||"Tanpa nama")+'</strong><small>'+esc(m.email)+'</small><small>'+esc(date(m.created_at))+'</small></td><td>'+esc(m.phone||"-")+'</td><td>'+esc(m.referral_code||"-")+'</td><td><small>'+esc(m.referred_by||"Tidak ada / tidak diketahui")+'</small></td><td>'+badge(m.referral_status)+'</td><td>'+badge(m.reseller_status)+'</td></tr>').join(""):'<tr><td colspan="6" class="admin-empty">Tidak ada anggota yang cocok.</td></tr>';
}
function renderMemberOptions(){
  const options=members.map(m=>'<option value="'+esc(m.id)+'">'+esc((m.full_name||m.email)+" — "+m.email)+'</option>').join("");
  $("paymentUser").innerHTML='<option value="">Pilih anggota</option>'+options;
  const balances=new Map();
  commissions.forEach(c=>balances.set(c.referrer_id,(balances.get(c.referrer_id)||0)+Number(c.amount||0)));
  payouts.filter(p=>p.status==="paid").forEach(p=>balances.set(p.user_id,(balances.get(p.user_id)||0)-Number(p.amount||0)));
  const payees=[...balances].filter(([,v])=>v>0).map(([id,v])=>{const m=members.find(x=>x.id===id);return m?'<option value="'+esc(id)+'">'+esc((m.full_name||m.email)+" — tersedia "+money(v))+'</option>':"";}).join("");
  $("payoutUser").innerHTML='<option value="">Pilih penerima komisi</option>'+payees;
  $("saleUser").innerHTML='<option value="">Pelanggan umum</option>'+members.map(m=>'<option value="'+esc(m.id)+'">'+esc((m.full_name||m.email)+" — "+m.email)+'</option>').join("");
}
async function createPayment(e){
  e.preventDefault();
  const user=$("paymentUser").value,type=$("paymentType").value,amount=Number($("paymentAmount").value);
  if(!user||!Number.isFinite(amount)||amount<=0){notice("Pilih anggota dan nominal pembayaran yang benar.","error");return;}
  const b=e.submitter;b.disabled=true;
  try{
    await rpc("admin_create_payment",{p_user_id:user,p_type:type,p_amount:amount,p_method:$("paymentMethod").value.trim(),p_reference:$("paymentReference").value.trim()||null,p_proof_url:$("paymentProof").value.trim()||null,p_notes:$("paymentNotes").value.trim()||null});
    $("paymentForm").reset();$("paymentAmount").value=150000;await loadAll();showTab("payments");
    notice("Pembayaran dicatat dengan status MENUNGGU. Verifikasi setelah bukti diperiksa.","success");
  }catch(err){notice("Gagal mencatat pembayaran: "+err.message,"error");}
  finally{b.disabled=false;}
}
function renderPayments(){
  const q=$("paymentSearch").value.trim().toLowerCase(),filter=$("paymentFilter").value;
  const list=payments.filter(p=>(!filter||p.status===filter)&&[p.email,p.full_name,p.reference_code,p.payment_method].join(" ").toLowerCase().includes(q));
  $("paymentsBody").innerHTML=list.length?list.map(p=>{
    const proofUrl=(()=>{try{const u=new URL(p.proof_url);return ["https:","http:"].includes(u.protocol)?u.href:"";}catch{return "";}})();
    const proof=proofUrl?'<a href="'+esc(proofUrl)+'" target="_blank" rel="noopener noreferrer">Buka bukti</a>':"Tidak ada";
    const actions=p.status==="pending"?'<div class="admin-actions"><button data-review="verified" data-id="'+esc(p.id)+'">Verifikasi</button><button class="admin-danger" data-review="rejected" data-id="'+esc(p.id)+'">Tolak</button></div>':badge(p.status);
    return '<tr><td><strong>'+esc(p.full_name||"-")+'</strong><small>'+esc(p.email)+'</small></td><td>'+esc(p.membership_type==="referral"?"Referral Member":"Reseller Member")+'</td><td>'+money(p.amount)+'<small>'+esc(p.payment_method)+'</small></td><td>'+esc(p.reference_code||"-")+'<small>'+proof+'</small></td><td>'+badge(p.status)+'</td><td>'+esc(date(p.created_at))+'</td><td>'+actions+'</td></tr>';
  }).join(""):'<tr><td colspan="7" class="admin-empty">Belum ada pembayaran.</td></tr>';
  $("paymentsBody").querySelectorAll("[data-review]").forEach(b=>b.addEventListener("click",()=>reviewPayment(b.dataset.id,b.dataset.review)));
}
async function reviewPayment(id,decision){
  const verb=decision==="verified"?"VERIFIKASI":"TOLAK";
  if(!confirm("Yakin "+verb+" pembayaran ini? "+(decision==="verified"?"Membership akan diaktifkan dan komisi referral dapat dibuat otomatis.":"Status pembayaran menjadi ditolak.")))return;
  const notes=prompt("Catatan admin (opsional):")||null;
  try{await rpc("admin_review_payment",{p_payment_id:id,p_decision:decision,p_notes:notes});await loadAll();notice("Pembayaran berhasil diproses: "+decision+".","success");}
  catch(e){notice("Gagal memproses pembayaran: "+e.message,"error");}
}
function renderCommissions(){
  $("commissionsBody").innerHTML=commissions.length?commissions.map(c=>'<tr><td><strong>'+esc(c.full_name||"-")+'</strong><small>'+esc(c.email)+'</small></td><td>'+esc(c.referred_email)+'</td><td>'+money(c.amount)+'</td><td>'+esc(date(c.created_at))+'</td></tr>').join(""):'<tr><td colspan="4" class="admin-empty">Belum ada komisi. Komisi dibuat ketika referral baru membayar dan pembayaran diverifikasi.</td></tr>';
}
async function createPayout(e){
  e.preventDefault();const user=$("payoutUser").value,amount=Number($("payoutAmount").value);
  if(!user||!amount||amount<=0){notice("Pilih penerima dan nominal pencairan.","error");return;}
  if(!confirm("Konfirmasi bahwa dana "+money(amount)+" sudah benar-benar ditransfer ke penerima?"))return;
  const b=e.submitter;b.disabled=true;
  try{await rpc("admin_record_payout",{p_user_id:user,p_amount:amount,p_reference:$("payoutReference").value.trim()||null,p_notes:$("payoutNotes").value.trim()||null});$("payoutForm").reset();await loadAll();showTab("commissions");notice("Pencairan komisi berhasil dicatat.","success");}
  catch(err){notice("Gagal mencatat pencairan: "+err.message,"error");}
  finally{b.disabled=false;}
}
function renderPayouts(){
  $("payoutsBody").innerHTML=payouts.length?payouts.map(p=>'<tr><td><strong>'+esc(p.full_name||"-")+'</strong><small>'+esc(p.email)+'</small></td><td>'+money(p.amount)+'</td><td>'+esc(p.payment_reference||"-")+'</td><td>'+esc(date(p.paid_at||p.created_at))+'</td><td>'+badge(p.status)+'</td></tr>').join(""):'<tr><td colspan="5" class="admin-empty">Belum ada pencairan komisi.</td></tr>';
}
function renderProducts(){
  const q=$("productSearch").value.trim().toLowerCase(),v=$("productVisibility").value;
  const list=products.filter(p=>(p.product+" "+p.variant).toLowerCase().includes(q)&&(v==="active"?p.is_active:v==="hidden"?!p.is_active:true));
  $("productsBody").innerHTML=list.length?list.map(p=>'<tr><td><strong>'+esc(p.product)+'</strong><small>'+esc(p.variant)+'</small></td><td>'+priceLabel(p.public_price)+'</td><td>'+priceLabel(p.reseller_price)+'</td><td>'+badge(p.in_stock?"active":"inactive")+'</td><td>'+badge(p.is_active?"active":"inactive")+'</td><td><div class="admin-actions"><button data-edit="'+esc(p.id)+'">Edit</button><button class="admin-danger" data-archive="'+esc(p.id)+'">'+(p.is_active?"Sembunyikan":"Aktifkan")+'</button></div></td></tr>').join(""):'<tr><td colspan="6" class="admin-empty">Produk tidak ditemukan.</td></tr>';
  $("productsBody").querySelectorAll("[data-edit]").forEach(b=>b.addEventListener("click",()=>editProduct(b.dataset.edit)));
  $("productsBody").querySelectorAll("[data-archive]").forEach(b=>b.addEventListener("click",()=>toggleProduct(b.dataset.archive)));
}
function editProduct(id){
  const p=products.find(x=>x.id===id);if(!p)return;
  $("productId").value=p.id;$("productName").value=p.product;$("productVariant").value=p.variant;
  $("productPublic").value=p.public_price??"";$("productReseller").value=p.reseller_price??"";
  $("productSort").value=p.sort_order??0;$("productStock").checked=p.in_stock;$("productActive").checked=p.is_active;
  $("productName").focus();window.scrollTo({top:0,behavior:"smooth"});
}
function resetProductForm(){$("productForm").reset();$("productId").value="";$("productSort").value=0;$("productStock").checked=true;$("productActive").checked=true;}
async function saveProduct(e){
  e.preventDefault();const id=$("productId").value||null;
  const val=id=>$(id).value.trim();
  const parsePrice=id=>val(id)===""?null:Number(val(id));
  const pub=parsePrice("productPublic"),res=parsePrice("productReseller");
  if((pub!==null&&(!Number.isFinite(pub)||pub<0))||(res!==null&&(!Number.isFinite(res)||res<0))){notice("Harga harus berupa angka nol atau lebih.","error");return;}
  const b=e.submitter;b.disabled=true;
  try{await rpc("admin_save_product",{p_id:id,p_product:val("productName"),p_variant:val("productVariant"),p_public_price:pub,p_reseller_price:res,p_in_stock:$("productStock").checked,p_is_active:$("productActive").checked,p_sort_order:Number(val("productSort")||0)});resetProductForm();await loadAll();showTab("products");notice("Produk tersimpan. Katalog toko akan membaca data terbaru dari Supabase.","success");}
  catch(err){notice("Gagal menyimpan produk: "+err.message,"error");}
  finally{b.disabled=false;}
}
async function toggleProduct(id){
  const p=products.find(x=>x.id===id);if(!p)return;
  const active=!p.is_active;if(!confirm((active?"Tampilkan":"Sembunyikan")+" "+p.product+" — "+p.variant+"?"))return;
  try{await rpc("admin_save_product",{p_id:id,p_product:p.product,p_variant:p.variant,p_public_price:p.public_price,p_reseller_price:p.reseller_price,p_in_stock:p.in_stock,p_is_active:active,p_sort_order:p.sort_order});await loadAll();notice("Visibilitas produk diperbarui.","success");}
  catch(e){notice("Gagal mengubah produk: "+e.message,"error");}
}

function renderSales(){
 const labels={pending:"Menunggu",paid:"Dibayar",fulfilled:"Selesai",cancelled:"Dibatalkan"};
 $("salesBody").innerHTML=sales.length?sales.map(s=>{
  const actions=s.status==="cancelled"?"":'<div class="admin-actions">'+["pending","paid","fulfilled","cancelled"].filter(x=>x!==s.status).map(x=>'<button data-sale-status="'+x+'" data-id="'+esc(s.id)+'">'+labels[x]+'</button>').join("")+'</div>';
  return '<tr><td><strong>'+esc(s.customer_name)+'</strong><small>'+esc(s.customer_contact||"-")+'</small></td><td>'+esc(s.product)+'<small>'+esc(s.variant)+'</small></td><td>'+esc(s.quantity)+'</td><td>'+money(s.unit_price*s.quantity)+'</td><td>'+money(s.cost_price*s.quantity)+'</td><td>'+badge(s.status)+'</td><td>'+esc(date(s.created_at))+actions+'</td></tr>';
 }).join(""):'<tr><td colspan="7" class="admin-empty">Belum ada penjualan.</td></tr>';
 $("salesBody").querySelectorAll("[data-sale-status]").forEach(b=>b.addEventListener("click",async()=>{
  if(!confirm("Ubah status transaksi ini menjadi "+labels[b.dataset.saleStatus]+"?"))return;
  try{await rpc("admin_update_sale_status",{p_sale_id:b.dataset.id,p_status:b.dataset.saleStatus,p_notes:null});await loadAll();notice("Status penjualan diperbarui.","success");}
  catch(e){notice("Gagal mengubah status: "+e.message,"error");}
 }));
}
async function createSale(e){
 e.preventDefault();const val=id=>$(id).value.trim(),q=Number(val("saleQuantity")),price=Number(val("salePrice")),cost=Number(val("saleCost"));
 if(q<1||price<0||cost<0){notice("Jumlah dan harga tidak valid.","error");return;}
 const b=e.submitter;b.disabled=true;
 try{
  await rpc("admin_create_sale",{p_user_id:val("saleUser")||null,p_customer_name:val("saleCustomer"),p_contact:val("saleContact"),p_product:val("saleProduct"),p_variant:val("saleVariant"),p_quantity:q,p_unit_price:price,p_cost_price:cost,p_status:val("saleStatus"),p_method:val("saleMethod"),p_reference:val("saleReference"),p_notes:val("saleNotes")});
  $("saleForm").reset();$("saleQuantity").value=1;$("saleCost").value=0;await loadAll();showTab("sales");notice("Penjualan berhasil dicatat.","success");
 }catch(err){notice("Gagal mencatat penjualan: "+err.message,"error");}finally{b.disabled=false;}
}
function renderPayoutRequests(){
 const labels={pending:"Menunggu",approved:"Disetujui",rejected:"Ditolak"};
 $("requestsBody").innerHTML=payoutRequests.length?payoutRequests.map(r=>{
  const actions=r.status==="pending"?'<div class="admin-actions"><button data-request="approved" data-id="'+esc(r.id)+'">Setujui</button><button class="admin-danger" data-request="rejected" data-id="'+esc(r.id)+'">Tolak</button></div>':r.status==="approved"?'<button data-request-paid="'+esc(r.id)+'">Catat transfer selesai</button>':badge(r.status);
  return '<tr><td><strong>'+esc(r.full_name||"-")+'</strong><small>'+esc(r.email)+'</small></td><td>'+money(r.amount)+'</td><td>'+esc(r.payout_method)+'<small>'+esc(r.payout_account)+'</small></td><td>'+esc(r.notes||"-")+'</td><td>'+badge(r.status)+'<small>'+esc(r.admin_notes||"")+'</small></td><td>'+esc(date(r.created_at))+actions+'</td></tr>';
 }).join(""):'<tr><td colspan="6" class="admin-empty">Belum ada pengajuan.</td></tr>';
 $("requestsBody").querySelectorAll("[data-request-paid]").forEach(b=>b.addEventListener("click",async()=>{
  if(!confirm("Pastikan dana sudah benar-benar ditransfer ke rekening anggota. Lanjutkan?"))return;
  const reference=prompt("Nomor referensi transfer (opsional):")||null;
  const notes=prompt("Catatan transfer (opsional):")||null;
  try{await rpc("admin_complete_payout_request",{p_request_id:b.dataset.requestPaid,p_reference:reference,p_notes:notes});await loadAll();notice("Transfer dicatat dan saldo komisi diperbarui.","success");}
  catch(e){notice("Gagal mencatat transfer: "+e.message,"error");}
 }));
 $("requestsBody").querySelectorAll("[data-request]").forEach(b=>b.addEventListener("click",async()=>{
  if(!confirm((b.dataset.request==="approved"?"Setujui":"Tolak")+" pengajuan ini?"))return;
  const notes=prompt("Catatan admin (opsional):")||null;
  try{await rpc("admin_review_payout_request",{p_request_id:b.dataset.id,p_decision:b.dataset.request,p_notes:notes});await loadAll();notice("Pengajuan pencairan diproses.","success");}
  catch(e){notice("Gagal memproses pengajuan: "+e.message,"error");}
 }));
}

function renderReports(){
 $("salesCount").textContent=salesSummary.orders??0;$("salesRevenue").textContent=money(salesSummary.revenue);$("salesCost").textContent=money(salesSummary.cost);$("salesProfit").textContent=money(salesSummary.profit);
  $("reportCount").textContent=payments.length;
  $("reportPending").textContent=payments.filter(p=>p.status==="pending").length;
  $("reportVerified").textContent=payments.filter(p=>p.status==="verified").length;
  $("reportRejected").textContent=payments.filter(p=>p.status==="rejected").length;
  const months=new Map();
  payments.filter(p=>p.status==="verified").forEach(p=>{
    const d=new Date(p.verified_at||p.created_at),key=d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0");
    const item=months.get(key)||{referral:0,reseller:0,total:0};
    item[p.membership_type]+=Number(p.amount);item.total+=Number(p.amount);months.set(key,item);
  });
  const list=[...months.entries()].sort((a,b)=>b[0].localeCompare(a[0]));
  $("reportBody").innerHTML=list.length?list.map(([month,v])=>'<tr><td>'+esc(month)+'</td><td>'+money(v.referral)+'</td><td>'+money(v.reseller)+'</td><td><strong>'+money(v.total)+'</strong></td></tr>').join(""):'<tr><td colspan="4" class="admin-empty">Belum ada pembayaran terverifikasi.</td></tr>';
}
function renderAudit(items){
  $("auditBody").innerHTML=items.length?items.map(a=>'<tr><td>'+esc(a.admin_email||"-")+'</td><td>'+esc(a.action)+'</td><td>'+esc(a.entity_type)+'<small>'+esc(a.entity_id||"-")+'</small></td><td><small>'+esc(JSON.stringify(a.details||{}))+'</small></td><td>'+esc(date(a.created_at))+'</td></tr>').join(""):'<tr><td colspan="5" class="admin-empty">Belum ada aktivitas tercatat.</td></tr>';
}
async function logout(){if(!db)return;const r=await db.auth.signOut();if(r.error){notice("Gagal keluar: "+r.error.message,"error");return;}location.href="index.html";}
start();
