import json
import os
import platform
import re
import time
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

# Optional Google LiteRT-LM (MediaPipe LLM Inference desktop successor) runtime detection
_LITERT_ENGINE = None
_LITERT_MODEL_PATH = None


def _detect_local_gemma_model():
    """Searches standard Windows 10+, macOS (M2 arm64 & Hackintosh x86_64), and Debian/Ubuntu paths."""
    home = os.path.expanduser("~")
    candidates = [
        os.environ.get("CARECONNECT_GEMMA_MODEL_PATH", ""),
        os.path.join(home, "Downloads", "gemma-2b.litertlm"),
        os.path.join(home, "Downloads", "gemma-2b.bin"),
        os.path.join(home, "Downloads", "gemma-2b-it-gpu-int4.bin"),
        os.path.join(home, "Models", "gemma-2b.litertlm"),
        os.path.join(home, "Models", "gemma-2b.bin"),
    ]
    for path in candidates:
        if path and os.path.isfile(path) and os.path.getsize(path) > 0:
            return path
    return None


def _init_litert_if_available():
    """Initializes Google LiteRT-LM Python engine if installed and a local model file exists."""
    global _LITERT_ENGINE, _LITERT_MODEL_PATH
    model_path = _detect_local_gemma_model()
    _LITERT_MODEL_PATH = model_path
    if not model_path:
        return
    try:
        from litert_lm import Engine  # type: ignore
        # Use GPU (Metal on M2 Mac / OpenCL-Vulkan on Desktop) with automatic CPU fallback for VMs/Hackintosh
        try:
            _LITERT_ENGINE = Engine(model_path=model_path, backend="gpu")
        except Exception:
            _LITERT_ENGINE = Engine(model_path=model_path, backend="cpu")
        print(f"[Colibri Local Server] Loaded Google LiteRT-LM engine from {model_path}")
    except Exception:
        _LITERT_ENGINE = None


def _try_litert_or_ollama_generation(prompt: str):
    """Attempts generation via Google LiteRT-LM or local Ollama gemma2:2b if available."""
    if _LITERT_ENGINE is not None:
        try:
            conv = _LITERT_ENGINE.create_conversation()
            resp = conv.send_message(prompt)
            if resp and str(resp).strip():
                return str(resp).strip(), "gemma-2b-mediapipe"
        except Exception:
            pass

    # Optional local Ollama (gemma2:2b) fallback on 127.0.0.1:11434 if running on the VM/host
    if os.environ.get("CARECONNECT_USE_OLLAMA", "0") == "1":
        try:
            req_data = json.dumps({
                "model": os.environ.get("CARECONNECT_OLLAMA_MODEL", "gemma2:2b"),
                "prompt": prompt,
                "stream": False,
            }).encode("utf-8")
            req = urllib.request.Request(
                "http://127.0.0.1:11434/api/generate",
                data=req_data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=8) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
                text = (payload.get("response") or "").strip()
                if text:
                    return text, "gemma-2b-mediapipe"
        except Exception:
            pass

    return None, None


class ColibriHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()

    def do_OPTIONS(self):
        self._set_headers(200)

    def do_GET(self):
        if self.path.startswith('/v1/models') or self.path.startswith('/models'):
            self._set_headers(200)
            response = {
                "object": "list",
                "platform": f"{platform.system()} ({platform.machine()})",
                "litert_model_loaded": _LITERT_ENGINE is not None,
                "data": [
                    {
                        "id": "olmoe-colibri",
                        "object": "model",
                        "created": int(time.time()),
                        "owned_by": "careconnect-edge"
                    },
                    {
                        "id": "gemma-2b-mediapipe",
                        "object": "model",
                        "created": int(time.time()),
                        "owned_by": "google-ai-edge-litert"
                    }
                ]
            }
            self.wfile.write(json.dumps(response).encode('utf-8'))
        elif self.path == '/' or self.path == '/health':
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "healthy",
                "service": "colibri-edge-router",
                "os": platform.system(),
                "arch": platform.machine(),
                "litert_ready": _LITERT_ENGINE is not None,
                "model_path": _LITERT_MODEL_PATH or "built-in-clinical-edge"
            }).encode('utf-8'))
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))

    def do_POST(self):
        if self.path.startswith('/v1/chat/completions') or self.path.startswith('/chat/completions'):
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)

            try:
                data = json.loads(body)
            except Exception:
                data = {}

            requested_model = data.get('model') or 'olmoe-colibri'
            messages = data.get('messages', [])
            user_msg = ""
            for m in messages:
                if m.get('role') == 'user':
                    user_msg = m.get('content', '')

            lower = user_msg.lower()

            spanish_patterns = [
                r'\bhola\b', r'\bdoctora\b', r'\bm[eé]dico\b', r'\bcita[s]?\b', r'\bojos\b',
                r'\boftalm[oó]logo\b', r'\boculista\b', r'\bmedicamento[s]?\b', r'\bpastilla[s]?\b',
                r'\breceta[s]?\b', r'\bprescripci[oó]n(es)?\b', r'\bmedicina[s]?\b',
                r'\bqui[eé]n\b', r'\bcu[aá]ndo\b', r'\bc[oó]mo\b', r'\bd[oó]nde\b',
                r'\bcu[aá]l\b', r'\bbuenos d[ií]as\b', r'\bbuenas tardes\b', r'\bgracias\b',
                r'\bpor favor\b', r'\bmi doctor\b', r'\bel doctor\b', r'\bun doctor\b'
            ]
            is_spanish = any(re.search(p, lower) for p in spanish_patterns)

            # 1. Clinical safety: Dosage alterations
            if any(k in lower for k in ['cut', 'split', 'halve', 'half', 'double', 'increase', 'decrease', 'cortar', 'dividir', 'mitad', 'aumentar', 'disminuir']) and any(k in lower for k in ['dose', 'dosage', 'pill', 'pills', 'medication', 'medicine', 'dosis', 'pastilla', 'pastillas', 'medicamento']):
                if is_spanish:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] No puedo autorizar la modificación de dosis de medicamentos recetados en el dispositivo. Derivando directamente a su equipo de atención médica."
                else:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] I cannot advise on modifying prescription medication dosages on-device. Escalating directly to your clinical care team."

            # 2. Multi-campus / directory lookups
            elif any(k in lower for k in ['other office', 'other clinic', 'another location', 'second campus', 'different office', 'otra clinica', 'otra clínica', 'otra oficina']):
                if is_spanish:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Consultando el directorio de instalaciones multicampus a través de la nube de CareConnect."
                else:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Looking up multi-campus directory listings via CareConnect Cloud."

            # 3. Emergency & acute symptoms
            elif any(k in lower for k in ['chest pain', 'shortness of breath', 'severe rash', 'bleeding', 'emergency', 'dolor de pecho', 'falta de aire', 'sangrado', 'emergencia']):
                if is_spanish:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Posible síntoma agudo detectado. Por favor busque atención médica de emergencia o comuníquese con su médico de inmediato."
                else:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Potential acute symptom detected. Please seek emergency medical assistance or contact your primary physician immediately."

            # 4. Doctor / Physician inquiries
            elif any(k in lower for k in ['who is my doctor', 'my doctor', 'doctor name', 'physician', 'pcp', 'primary care', 'provider', 'quien es mi doctor', 'quién es mi doctor', 'quien es mi medico', 'quién es mi médico']):
                if is_spanish:
                    reply = "Su médica de atención primaria es la Dra. Sarah Mitchell en Medicina Familiar de CareConnect. Su consultorio está ubicado en el campus principal y el teléfono de contacto es (555) 0101."
                else:
                    reply = "Your primary care physician is Dr. Sarah Mitchell at CareConnect Family Medicine. Her office is located at the Main Medical Pavilion, phone (555) 0101."

            # 5. Eye doctor / Optometrist / Ophthalmologist
            elif any(k in lower for k in ['eye doctor', 'eye', 'optometrist', 'ophthalmologist', 'vision', 'glasses', 'ojos', 'oftalmologo', 'oftalmólogo', 'oculista', 'vista']):
                if is_spanish:
                    reply = "Para el cuidado de la vista y optometría, su red incluye al Dr. Robert Chen en Metro Vision Center. Si necesita programar un examen de la vista, puedo solicitar una referencia a la Dra. Mitchell."
                else:
                    reply = "For vision and eye care, CareConnect partners with Dr. Robert Chen at Metro Vision Center. If you need a comprehensive eye exam, would you like me to request a referral from Dr. Mitchell?"

            # 6. Appointments & schedules
            elif any(k in lower for k in ['appointment', 'schedule', 'visit', 'check-in', 'when is my', 'cita', 'citas', 'horario', 'cuando es mi', 'cuándo es mi']):
                if is_spanish:
                    reply = "Su próxima visita programada es con la Dra. Sarah Mitchell a las 10:00 AM este jueves. La asistencia de transporte médico ya está confirmada."
                else:
                    reply = "Your next scheduled check-in is with Dr. Sarah Mitchell at 10:00 AM on Thursday. Transportation assistance is currently active and confirmed."

            # 7. Active medications
            elif any(k in lower for k in [
                'my medications', 'what medications', 'what medicine', 'prescriptions', 'prescription', 'medication', 'medications',
                'mis medicamentos', 'medicamento', 'medicamentos', 'que medicinas', 'qué medicinas', 'medicina', 'medicinas',
                'receta', 'recetas', 'prescripcion', 'prescripción', 'prescripciones', 'pastilla', 'pastillas'
            ]):
                if is_spanish:
                    reply = "Sus medicamentos activos registrados son Lisinopril (10 mg diarios para la presión arterial) y Metformina (500 mg dos veces al día con alimentos)."
                else:
                    reply = "Your active medications on file are Lisinopril (10mg once daily for blood pressure) and Metformin (500mg twice daily with meals)."

            # 8. Greetings (English & Spanish)
            elif any(k in lower for k in ['hello', 'hi', 'hey', 'good morning', 'good afternoon', 'hola', 'buenos dias', 'buenos días', 'buenas tardes']):
                if is_spanish:
                    reply = "¡Hola Mary! Soy su asistente local de CareConnect en su dispositivo. ¿En qué puedo ayudarle hoy con su salud o citas?"
                else:
                    reply = "Hello Mary! I am your CareConnect On-Device Edge Assistant. How can I help you manage your health, medications, or appointments today?"

            # 9. Try local Google LiteRT-LM / Ollama Gemma-2B if loaded, otherwise escalate to Cloud AI
            else:
                llm_reply, llm_model = _try_litert_or_ollama_generation(user_msg)
                if llm_reply:
                    reply = llm_reply
                    requested_model = llm_model or requested_model
                elif is_spanish:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Consultando su expediente médico completo a través de la IA clínica de CareConnect para responder con precisión."
                else:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Reviewing your comprehensive medical records and clinical guidelines via CareConnect Cloud AI."

            response = {
                "id": f"chatcmpl-{int(time.time()*1000)}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": requested_model,
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": reply
                        },
                        "finish_reason": "stop"
                    }
                ],
                "usage": {
                    "prompt_tokens": len(user_msg.split()) + 10,
                    "completion_tokens": len(reply.split()),
                    "total_tokens": len(user_msg.split()) + len(reply.split()) + 10
                }
            }

            self._set_headers(200)
            self.wfile.write(json.dumps(response).encode('utf-8'))
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))

    def log_message(self, format, *args):
        print(f"[Colibri Local Server] {self.address_string()} - {format % args}")


def run(port=8000):
    _init_litert_if_available()
    server = HTTPServer(('0.0.0.0', port), ColibriHandler)
    print(
        f"Colibri + Google LiteRT-LM Local Server running on port {port} "
        f"(http://0.0.0.0:{port}) [{platform.system()} {platform.machine()}]"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    run()
