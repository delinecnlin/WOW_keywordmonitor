"use strict";
const byId = id => document.getElementById(id);
const state = {token:sessionStorage.getItem("market_token") || ""};
byId("token").value = state.token;
function text(id, value) {byId(id).textContent = value == null ? "—" : String(value);}
function row(tbody, cells) {
  const tr = document.createElement("tr");
  for (const cell of cells) {
    const td = document.createElement("td");
    td.textContent = String(cell ?? "—");
    tr.appendChild(td);
  }
  tbody.appendChild(tr);
}
function fillTable(id, records, fields) {
  const tbody = byId(id).querySelector("tbody");
  tbody.replaceChildren();
  if (!records.length) row(tbody, ["没有可显示的数据"]);
  for (const item of records) row(tbody, fields.map(f => f(item)));
}
function fmtTime(s) {return s ? new Date(s * 1000).toLocaleString("zh-CN") : "—";}
function copperToGold(v) {return v == null ? "—" : (Number(v) / 10000).toFixed(2);}
async function api(path, options={}) {
  const response = await fetch(path, {
    ...options, headers: {...(options.headers || {}), Authorization:"Bearer " + state.token}
  });
  if (!response.ok) throw new Error(path + ": HTTP " + response.status);
  return await response.json();
}
function plot(data) {
  const svg=byId("chart");svg.replaceChildren();
  const points = data.filter(x => x.min_unit_copper > 0).reverse();
  if (points.length < 2) {text("chartnote","至少需要两个有效扫描快照才能绘制价格趋势。");return;}
  const vals = points.map(x => x.min_unit_copper / 10000);
  const lo=Math.min(...vals), hi=Math.max(...vals);const span=Math.max(hi-lo,1);
  const xy = vals.map((v,i)=>[35 + (i * 710 / (vals.length-1)),200-(v-lo)*150/span]);
  function line(x1,y1,x2,y2,color,width) {
    const l=document.createElementNS("http://www.w3.org/2000/svg","line");
    for (const [k,v] of Object.entries({x1,y1,x2,y2,stroke:color,"stroke-width":width})) l.setAttribute(k,v);
    svg.appendChild(l);
  }
  for(let i=0;i<4;i++) line(35,50+i*50,745,50+i*50,"#31435c",1);
  const p=document.createElementNS("http://www.w3.org/2000/svg","polyline");
  p.setAttribute("points",xy.map(c=>c.join(",")).join(" "));
  p.setAttribute("fill","none");p.setAttribute("stroke","#72b2ff");p.setAttribute("stroke-width","3");svg.appendChild(p);
  text("chartnote", "快照: "+points.length+"，观察最低买断单价（金币）: "+lo.toFixed(2)+"–"+hi.toFixed(2)+"。非真实成交价。");
}
async function refresh() {
  if(!state.token) {text("status","请输入 Token");return;}
  try {
    const [overview,sellers,history,golds]=await Promise.all([
      api("/api/overview"),api("/api/sellers"),api("/api/history?limit=300"),api("/api/gold-quotes?limit=30")
    ]);
    text("status","已连接");
    if(overview.status==="ok") {
      const scan=overview.scan;
      text("realm",scan.realm+" / "+(scan.faction==="Alliance"?"联盟":scan.faction));
      const item=(overview.items||[]).find(x=>x.name==="黑莲花");
      text("lotusQty",item?.visible_qty ?? "当前页未见");
      fillTable("items",overview.items,[
        x=>x.name,x=>x.visible_qty,x=>copperToGold(x.min_unit_copper)
      ]);
    }
    if(sellers.status==="ok") {
      text("coverage",sellers.known_fraction == null ? "不可用" : (sellers.known_fraction*100).toFixed(1)+"%");
      fillTable("sellers",sellers.sellers || [],[x=>x.character,x=>x.visible_qty]);
      text("sellerNote","HHI(仅已知角色): "+(sellers.hhi_known_only?.toFixed(3)??"—")+"。不能判断真实账号或工作室身份。");
    }
    plot(history.snapshots || []);
    text("gold",golds.quotes.length ? "¥"+Number(golds.quotes[0].yuan_per_1000g).toFixed(2) : "—");
    fillTable("goldTable",golds.quotes.slice(0,15),[
      x=>fmtTime(x.observed_at),x=>"¥"+x.yuan_per_1000g,x=>x.source,x=>x.notes
    ]);
  } catch(err) {text("status","连接失败: "+err.message);}
}
byId("connect").addEventListener("click",()=>{state.token=byId("token").value.trim();sessionStorage.setItem("market_token",state.token);refresh();});
byId("quoteForm").addEventListener("submit",async ev=>{
  ev.preventDefault();
  try {
    const body={observed_at:Math.floor(Date.now()/1000),yuan_per_1000g:Number(byId("quotePrice").value),
      realm:"硬核服",faction:"Alliance",source:"manual_7881_reference",notes:byId("quoteNotes").value};
    if(byId("quoteDepth").value!=="") body.visible_depth_1000g=Number(byId("quoteDepth").value);
    await api("/api/gold-quotes",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});
    byId("quoteForm").reset();await refresh();
  }catch(err){text("status","保存失败: "+err.message);}
});
if(state.token) refresh();
