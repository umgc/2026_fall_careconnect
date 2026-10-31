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


def _resolve_litert_backend(backend_cls, attr_name: str):
    """Creates a LiteRT-LM Backend object (e.g., Backend.GPU() or Backend.CPU())."""
    member = getattr(backend_cls, attr_name)
    return member() if callable(member) else member


def _extract_litert_text(response) -> str:
    """Extracts assistant text from a LiteRT-LM send_message dict or string response."""
    if response is None:
        return ""
    if isinstance(response, str):
        return response.strip()
    if isinstance(response, dict):
        content = response.get("content")
        if isinstance(content, list):
            parts = [
                str(item.get("text", ""))
                for item in content
                if isinstance(item, dict) and item.get("text")
            ]
            if parts:
                return "".join(parts).strip()
        if isinstance(response.get("text"), str):
            return response["text"].strip()
    return str(response).strip()


def _init_litert_if_available():
    """Initializes Google LiteRT-LM Python engine if installed and a local model file exists."""
    global _LITERT_ENGINE, _LITERT_MODEL_PATH
    model_path = _detect_local_gemma_model()
    _LITERT_MODEL_PATH = model_path
    if not model_path:
        return
    try:
        import litert_lm  # type: ignore

        gpu_backend = _resolve_litert_backend(litert_lm.Backend, "GPU")
        cpu_backend = _resolve_litert_backend(litert_lm.Backend, "CPU")
        # Use GPU (Metal on M2 Mac / OpenCL-Vulkan on Desktop) with automatic CPU fallback for VMs/Hackintosh
        try:
            engine = litert_lm.Engine(model_path, backend=gpu_backend)
            if hasattr(engine, "__enter__"):
                engine = engine.__enter__() or engine
        except Exception:
            engine = litert_lm.Engine(model_path, backend=cpu_backend)
            if hasattr(engine, "__enter__"):
                engine = engine.__enter__() or engine
        _LITERT_ENGINE = engine
        print(f"[Colibri Local Server] Loaded Google LiteRT-LM engine from {model_path}")
    except Exception:
        _LITERT_ENGINE = None


def _configured_ollama_model() -> str:
    """Returns the exact configured Ollama model tag."""
    return os.environ.get("CARECONNECT_OLLAMA_MODEL", "gemma2:2b").strip()


def _is_ollama_gemma_ready() -> bool:
    """Checks whether local Ollama fallback is explicitly enabled and serves the exact configured model tag."""
    if os.environ.get("CARECONNECT_USE_OLLAMA", "0") != "1":
        return False
    target_model = _configured_ollama_model()
    if not target_model:
        return False
    expected_tags = (
        {target_model}
        if ":" in target_model
        else {target_model, f"{target_model}:latest"}
    )
    try:
        req = urllib.request.Request(
            "http://127.0.0.1:11434/api/tags",
            headers={"Accept": "application/json"},
            method="GET",
        )
        with urllib.request.urlopen(req, timeout=2) as resp:  # nosec B310
            if getattr(resp, "status", 200) != 200:
                return False
            payload = json.loads(resp.read().decode("utf-8"))
            models = payload.get("models") or []
            for item in models:
                if not isinstance(item, dict):
                    continue
                name = str(item.get("name") or item.get("model") or "").strip()
                if name in expected_tags:
                    return True
    except Exception:
        return False
    return False


def _is_gemma_engine_ready() -> bool:
    """Returns True only when a real Gemma engine (LiteRT-LM or verified Ollama) is loaded."""
    return _LITERT_ENGINE is not None or _is_ollama_gemma_ready()


def _try_litert_or_ollama_generation(prompt: str):
    """Attempts generation via Google LiteRT-LM or local Ollama gemma2:2b if available."""
    if _LITERT_ENGINE is not None:
        try:
            conv = _LITERT_ENGINE.create_conversation()
            if hasattr(conv, "__enter__") and hasattr(conv, "__exit__"):
                with conv as active_conv:
                    resp = active_conv.send_message(prompt)
            else:
                resp = conv.send_message(prompt)
            text = _extract_litert_text(resp)
            if text:
                return text, "gemma-2b-mediapipe"
        except Exception:
            pass

    # Optional local Ollama (gemma2:2b) fallback on 127.0.0.1:11434 if running on the VM/host
    if os.environ.get("CARECONNECT_USE_OLLAMA", "0") == "1":
        target_model = _configured_ollama_model()
        if not target_model:
            return None, None
        try:
            req_data = json.dumps({
                "model": target_model,
                "prompt": prompt,
                "stream": False,
            }).encode("utf-8")
            req = urllib.request.Request(
                "http://127.0.0.1:11434/api/generate",
                data=req_data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=8) as resp:  # nosec B310
                payload = json.loads(resp.read().decode("utf-8"))
                text = (payload.get("response") or "").strip()
                if text:
                    return text, "gemma-2b-mediapipe"
        except Exception:
            pass

    return None, None


def _evaluate_clinical_safety_escalation(lower: str, is_spanish: bool):
    """Returns a clinical safety escalation reply if the query must route to Cloud AI, else None."""
    # 1. Clinical safety: Dosage alterations
    if any(
        k in lower
        for k in [
            "cut", "split", "halve", "half", "double", "increase", "decrease",
            "cortar", "dividir", "mitad", "aumentar", "disminuir",
        ]
    ) and any(
        k in lower
        for k in [
            "dose", "dosage", "pill", "pills", "medication", "medicine",
            "dosis", "pastilla", "pastillas", "medicamento",
        ]
    ):
        if is_spanish:
            return (
                "[ESCALATE_TO_CLINICAL_CLOUD] No puedo autorizar la modificación de dosis de "
                "medicamentos recetados en el dispositivo. Derivando directamente a su equipo "
                "de atención médica."
            )
        return (
            "[ESCALATE_TO_CLINICAL_CLOUD] I cannot advise on modifying prescription medication "
            "dosages on-device. Escalating directly to your clinical care team."
        )

    # 2. Multi-campus / directory lookups
    if any(
        k in lower
        for k in [
            "other office", "other clinic", "another location", "second campus",
            "different office", "otra clinica", "otra clínica", "otra oficina",
        ]
    ):
        if is_spanish:
            return (
                "[ESCALATE_TO_CLINICAL_CLOUD] Consultando el directorio de instalaciones "
                "multicampus a través de la nube de CareConnect."
            )
        return (
            "[ESCALATE_TO_CLINICAL_CLOUD] Looking up multi-campus directory listings "
            "via CareConnect Cloud."
        )

    # 3. Emergency & acute symptoms
    if any(
        k in lower
        for k in [
            "chest pain", "shortness of breath", "severe rash", "bleeding", "emergency",
            "dolor de pecho", "falta de aire", "sangrado", "emergencia",
        ]
    ):
        if is_spanish:
            return (
                "[ESCALATE_TO_CLINICAL_CLOUD] Posible síntoma agudo detectado. Por favor busque "
                "atención médica de emergencia o comuníquese con su médico de inmediato."
            )
        return (
            "[ESCALATE_TO_CLINICAL_CLOUD] Potential acute symptom detected. Please seek emergency "
            "medical assistance or contact your primary physician immediately."
        )

    return None


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
            gemma_ready = _is_gemma_engine_ready()
            models_data = [
                {
                    "id": "olmoe-colibri",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "careconnect-edge"
                }
            ]
            if gemma_ready:
                models_data.append({
                    "id": "gemma-2b-mediapipe",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "google-ai-edge-litert"
                })
            self._set_headers(200)
            response = {
                "object": "list",
                "platform": f"{platform.system()} ({platform.machine()})",
                "litert_model_loaded": _LITERT_ENGINE is not None,
                "gemma_ready": gemma_ready,
                "data": models_data
            }
            self.wfile.write(json.dumps(response).encode('utf-8'))
        elif self.path == '/' or self.path == '/health':
            gemma_ready = _is_gemma_engine_ready()
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "healthy",
                "service": "colibri-edge-router",
                "os": platform.system(),
                "arch": platform.machine(),
                "litert_ready": _LITERT_ENGINE is not None,
                "gemma_ready": gemma_ready,
                "model_path": _LITERT_MODEL_PATH if _LITERT_ENGINE is not None else None
            }).encode('utf-8'))
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))

    def do_POST(self):
        if self.path.startswith('/v1/chat/completions') or self.path.startswith('/chat/completions'):
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)

            try:
                data = json.loads(body) if body else {}
            except Exception:
                self._set_headers(400)
                self.wfile.write(json.dumps({
                    "error": {
                        "message": "Invalid JSON request body.",
                        "type": "invalid_request_error",
                        "code": "INVALID_JSON",
                    }
                }).encode('utf-8'))
                return

            requested_model = str(data.get('model') or 'olmoe-colibri')
            is_gemma_request = (
                requested_model == 'gemma-2b-mediapipe'
                or 'gemma' in requested_model.lower()
            )

            if is_gemma_request and not _is_gemma_engine_ready():
                self._set_headers(503)
                self.wfile.write(json.dumps({
                    "error": {
                        "message": "Gemma engine is not loaded or ready.",
                        "type": "service_unavailable",
                        "code": "GEMMA_ENGINE_NOT_READY",
                    }
                }).encode('utf-8'))
                return

            messages = data.get('messages', [])
            user_msg = ""
            for m in messages:
                if isinstance(m, dict) and m.get('role') == 'user':
                    user_msg = str(m.get('content', ''))

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

            safety_reply = _evaluate_clinical_safety_escalation(lower, is_spanish)

            if safety_reply is not None:
                reply = safety_reply
            elif is_gemma_request:
                # Gemma requests must execute solely through a confirmed loaded Gemma engine
                # and never fall back to hardcoded clinical fixture responses.
                llm_reply, llm_model = _try_litert_or_ollama_generation(user_msg)
                if not llm_reply:
                    self._set_headers(503)
                    self.wfile.write(json.dumps({
                        "error": {
                            "message": "Gemma inference engine failed to produce a response.",
                            "type": "service_unavailable",
                            "code": "GEMMA_INFERENCE_UNAVAILABLE",
                        }
                    }).encode('utf-8'))
                    return
                reply = llm_reply
                requested_model = llm_model or "gemma-2b-mediapipe"
            elif _is_gemma_engine_ready():
                # When a real local engine is loaded, execute real inference for ordinary desktop chat
                # rather than returning canned demo strings.
                llm_reply, llm_model = _try_litert_or_ollama_generation(user_msg)
                if llm_reply:
                    reply = llm_reply
                    requested_model = llm_model or requested_model
                elif is_spanish:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Consultando su expediente médico completo a través de la IA clínica de CareConnect para responder con precisión."
                else:
                    reply = "[ESCALATE_TO_CLINICAL_CLOUD] Reviewing your comprehensive medical records and clinical guidelines via CareConnect Cloud AI."

            # 4. Doctor / Physician inquiries (offline Colibri demo router when no engine is loaded)
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

            # 9. Escalate unhandled offline queries to Cloud AI
            else:
                if is_spanish:
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
    global _LITERT_ENGINE
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
        if _LITERT_ENGINE is not None and hasattr(_LITERT_ENGINE, "__exit__"):
            try:
                _LITERT_ENGINE.__exit__(None, None, None)
            except Exception:
                pass
            _LITERT_ENGINE = None


if __name__ == '__main__':
    run()
