export function window_location_origin() {
    return window.location.origin;
}

export function history_back() {
    window.history.back();
}

export function reload_page() {
    window.location.reload();
}

export function add_body_class(class_name) {
    document.body.classList.add(class_name);
}

export function submit_form(id) {
    let form = document.getElementById(id);
    if (form) {
        form.submit();
    }
}

export function get_file_size_from_submit_event(event) {
    try {
        let file = event.target.querySelector('input[type="file"]').files[0];
        return file ? file.size : 0;
    } catch (e) {
        return 0;
    }
}

export function navigate_to(url) {
    window.location.href = url;
}

let censor_ws = null;
let censor_ctx = null;
let censor_img_w = 0;
let censor_img_h = 0;

export function init_censor_ws(photo_id, img_w, img_h) {
    if (censor_ws) { censor_ws.close(); }
    censor_img_w = img_w;
    censor_img_h = img_h;
    censor_ctx = null;
  
    let proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    censor_ws = new WebSocket(proto + "//" + window.location.host + "/napi/censor/" + photo_id);
}

export function close_censor_ws() {
    if (censor_ws) {
	censor_ws.close();
	censor_ws = null;
    }
}

let sendTimeout = null;

export function draw_and_send_censor_mask(x, y, radius) {
    if (!censor_ctx) {
        let canvas = document.getElementById("censor-canvas");
        if (canvas) {
            censor_ctx = canvas.getContext("2d", { willReadFrequently: true });
        }
    }
    if (!censor_ctx) return;
  
    censor_ctx.fillStyle = "rgba(0, 0, 0, 1)";
    censor_ctx.beginPath();
    censor_ctx.arc(x, y, radius, 0, Math.PI * 2);
    censor_ctx.fill();
  
    if (sendTimeout) {
	clearTimeout(sendTimeout);
    }
  
    sendTimeout = setTimeout(() => {
	sendTimeout = null;
	send_current_mask();
    }, 1000);
}

function send_current_mask() {
    if (!censor_ws || censor_ws.readyState !== WebSocket.OPEN) return;

    let imgData = censor_ctx.getImageData(0, 0, censor_img_w, censor_img_h);
    let pixels = imgData.data;
  
    let rowBytes = censor_img_w * 4;
    let buffer = new Uint8Array(censor_img_h * (rowBytes + 1));
  
    for (let r = 0; r < censor_img_h; r++) {
	let destRowStart = r * (rowBytes + 1);
	buffer[destRowStart] = 0; 
	let srcRowStart = r * rowBytes;
	buffer.set(pixels.subarray(srcRowStart, srcRowStart + rowBytes), destRowStart + 1);
    }
  
    censor_ws.send(buffer);
}
