"use strict";
const byId = id => document.getElementById(id);
const report = {
  kind: "translation-compatibility-probe", startedAt: new Date().toISOString(),
  userAgent: navigator.userAgent, secureContext: isSecureContext,
  host: globalThis.chrome?.webview ? "WebView2" : "browser",
  offlineVerified: false, checks: []
};
let controller = null;
const pair = () => { const [sourceLanguage,targetLanguage] = byId("direction").value.split("-"); return {sourceLanguage,targetLanguage}; };
function record(value) { report.checks.push({at:new Date().toISOString(),onlineHint:navigator.onLine,...value}); byId("evidence").textContent = JSON.stringify(report,null,2); }
function supported() { return typeof globalThis.Translator?.availability === "function" && typeof globalThis.Translator?.create === "function"; }
byId("check").onclick = async () => {
  try {
    const languages = pair();
    const availability = supported() ? await Translator.availability(languages) : "api-absent";
    record({operation:"availability",...languages,availability});
    byId("status").textContent = availability === "api-absent" ? "Runtime này không cung cấp Translator API. Không thể dùng làm bộ dịch local." : "Trạng thái mô hình: " + availability;
  } catch(error) { record({operation:"availability",error:String(error)}); byId("status").textContent = String(error); }
};
byId("translate").onclick = async () => {
  if (controller) return;
  if (!supported()) { byId("status").textContent = "Translator API không có trong runtime này."; record({operation:"translation",error:"api-absent"}); return; }
  if (!byId("input").value.trim()) return;
  const languages = pair();
  controller = new AbortController();
  const current = controller;
  let session;
  const started = performance.now();
  byId("translate").disabled = true; byId("check").disabled = true; byId("direction").disabled = true; byId("cancel").disabled = false;
  byId("result").textContent = "";
  try {
    // create() runs directly from the click handler, preserving user activation for downloads.
    session = await Translator.create({...languages,signal:current.signal,monitor:m => m.addEventListener("downloadprogress",event => {
      byId("status").textContent = event.total > 0 ? "Tải mô hình: " + Math.round(event.loaded/event.total*100) + "%" : "Đang tải mô hình...";
    })});
    byId("status").textContent = "Đang dịch local...";
    const output = await session.translate(byId("input").value,{signal:current.signal});
    byId("result").textContent = output;
    record({operation:"translation",...languages,success:!!output.trim(),elapsedMs:Math.round(performance.now()-started)});
    byId("status").textContent = "Đã dịch. Cần thử lại khi ngắt mạng để xác minh offline; navigator.onLine không phải bằng chứng đủ.";
  } catch(error) { record({operation:"translation",...languages,error:String(error)}); byId("status").textContent = String(error); }
  finally {
    session?.destroy(); controller = null;
    byId("translate").disabled = false; byId("check").disabled = false; byId("direction").disabled = false; byId("cancel").disabled = true;
  }
};
byId("cancel").onclick = () => controller?.abort();
byId("save").onclick = () => {
  const url = URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:"application/json"}));
  const link = document.createElement("a"); link.href=url; link.download="translation-probe.json"; link.click();
  setTimeout(() => URL.revokeObjectURL(url),1000);
  byId("save-status").textContent = "Báo cáo không lưu nội dung văn bản thử. Offline chưa được tự xác nhận.";
};
addEventListener("pagehide",() => controller?.abort());
record({operation:"api-detection",present:supported()});
