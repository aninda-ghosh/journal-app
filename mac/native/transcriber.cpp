// Journal — on-device speech to text, streaming.
//
// Reads raw audio on stdin and writes words to stdout as they're recognised,
// so a sentence appears while it's still being spoken. Runs Whisper locally
// through whisper.cpp, which uses Metal on Apple Silicon. Nothing is uploaded
// and nothing is written to disk.
//
//   transcriber --diagnose <model.bin>
//   transcriber --stream   <model.bin> [language]
//       stdin : signed 16-bit little-endian mono PCM at 16 kHz
//       stdout: one JSON object per line —
//               {"type":"ready"}
//               {"type":"partial","text":"the fog didn't lift"}
//               {"type":"final","text":"The fog didn't lift until noon."}
//               {"type":"error","code":"...","message":"..."}
//
// Whisper works on windows of audio rather than word by word, so "live" here
// means the tail of what you've said is re-transcribed every few seconds and
// the guess improves. Older audio is committed and never revisited, which
// keeps every pass short no matter how long the ramble runs.

#include "whisper.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr int   SAMPLE_RATE   = 16000;
constexpr float STEP_SECONDS  = 2.5f;   // how often the tail is re-transcribed
constexpr float MAX_SECONDS   = 20.0f;  // longest window kept before committing
constexpr float TAIL_SEARCH   = 4.0f;   // where to hunt for a gap to cut at
constexpr float MIN_SECONDS   = 1.0f;   // whisper needs a moment of audio

std::mutex out_mutex;

void emit(const std::string& json) {
    std::lock_guard<std::mutex> lock(out_mutex);
    fputs(json.c_str(), stdout);
    fputc('\n', stdout);
    fflush(stdout);                     // the app is reading these live
}

std::string escape(const std::string& text) {
    std::string out;
    out.reserve(text.size() + 16);
    for (unsigned char c : text) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

void emitText(const char* type, const std::string& text) {
    emit(std::string("{\"type\":\"") + type + "\",\"text\":\"" + escape(text) + "\"}");
}

void emitError(const std::string& code, const std::string& message) {
    emit("{\"type\":\"error\",\"code\":\"" + escape(code) +
         "\",\"message\":\"" + escape(message) + "\"}");
}

std::string trim(const std::string& s) {
    const size_t first = s.find_first_not_of(" \t\n\r");
    if (first == std::string::npos) return "";
    const size_t last = s.find_last_not_of(" \t\n\r");
    return s.substr(first, last - first + 1);
}

/** Run one pass of Whisper over a window of audio. */
std::string transcribe(whisper_context* ctx, const std::vector<float>& audio,
                       const std::string& language, int threads) {
    if (audio.size() < static_cast<size_t>(MIN_SECONDS * SAMPLE_RATE)) return "";

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime   = false;
    params.print_progress   = false;
    params.print_timestamps = false;
    params.print_special    = false;
    params.translate        = false;
    params.no_timestamps    = true;
    params.single_segment   = false;
    params.suppress_blank   = true;
    params.n_threads        = threads;
    params.language         = language.c_str();

    if (whisper_full(ctx, params, audio.data(), static_cast<int>(audio.size())) != 0) {
        return "";
    }

    std::string text;
    const int segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < segments; i++) {
        const char* piece = whisper_full_get_segment_text(ctx, i);
        if (piece) text += piece;
    }
    return trim(text);
}

/**
 * Find a quiet moment near the end of the window to cut at, so a committed
 * chunk doesn't end mid-word. Falls back to the plain end if it's all loud.
 */
size_t findGap(const std::vector<float>& audio) {
    const size_t window = SAMPLE_RATE / 10;                       // 100 ms
    const size_t searchFrom = audio.size() > static_cast<size_t>(TAIL_SEARCH * SAMPLE_RATE)
        ? audio.size() - static_cast<size_t>(TAIL_SEARCH * SAMPLE_RATE)
        : 0;
    if (audio.size() < searchFrom + window * 2) return audio.size();

    size_t quietest = audio.size();
    double lowest = 1e9;

    for (size_t at = searchFrom; at + window <= audio.size(); at += window / 2) {
        double sum = 0;
        for (size_t i = at; i < at + window; i++) sum += audio[i] * audio[i];
        const double rms = std::sqrt(sum / window);
        if (rms < lowest) { lowest = rms; quietest = at + window / 2; }
    }
    return quietest;
}

int threadCount() {
    const unsigned hw = std::thread::hardware_concurrency();
    if (hw == 0) return 4;
    return static_cast<int>(hw > 8 ? 8 : hw);
}

whisper_context* loadModel(const char* path) {
    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;                 // Metal, on Apple Silicon
    return whisper_init_from_file_with_params(path, cparams);
}

}  // namespace

int main(int argc, char** argv) {
    whisper_log_set([](enum ggml_log_level, const char*, void*) {}, nullptr);

    const std::string mode  = argc > 1 ? argv[1] : "";
    const std::string model = argc > 2 ? argv[2] : "";
    const std::string language = argc > 3 && argv[3][0] ? argv[3] : "en";

    if (model.empty()) {
        emitError("no_model", "No speech model was given.");
        return 1;
    }

    if (mode == "--diagnose") {
        whisper_context* ctx = loadModel(model.c_str());
        if (!ctx) {
            emitError("model_failed", "The speech model couldn't be loaded from " + model);
            return 1;
        }
        const bool multilingual = whisper_is_multilingual(ctx) != 0;
        whisper_free(ctx);
        emit("{\"type\":\"ready\",\"code\":\"ok\",\"model\":\"" + escape(model) +
             "\",\"multilingual\":" + (multilingual ? "true" : "false") +
             ",\"threads\":" + std::to_string(threadCount()) +
             ",\"message\":\"The speech model loaded and is ready.\"}");
        return 0;
    }

    if (mode != "--stream") {
        emitError("bad_usage", "Usage: transcriber --stream <model> [lang] | --diagnose <model>");
        return 1;
    }

    const int threads = threadCount();

    std::mutex mutex;
    std::vector<float> incoming;
    std::atomic<bool> finished{false};

    // Audio is read on its own thread so a slow pass of Whisper never stalls
    // the pipe and drops the writer's words.
    std::thread reader([&] {
        std::vector<int16_t> raw(4096);
        while (true) {
            const size_t got = fread(raw.data(), sizeof(int16_t), raw.size(), stdin);
            if (got == 0) break;
            std::lock_guard<std::mutex> lock(mutex);
            for (size_t i = 0; i < got; i++) incoming.push_back(raw[i] / 32768.0f);
        }
        finished = true;
    });

    // Say we're ready *before* loading the model, and load it while the writer
    // is already talking. The model is ~190MB and takes a noticeable moment;
    // making someone watch "Starting…" every single time they press Dictate
    // would be a poor trade for a second of tidiness. The reader thread above
    // is already buffering, so nothing said during the load is lost.
    emit("{\"type\":\"ready\"}");

    whisper_context* ctx = loadModel(model.c_str());
    if (!ctx) {
        emitError("model_failed", "The speech model couldn't be loaded from " + model);
        return 1;
    }

    std::vector<float> window;     // audio not yet committed
    std::string committed;         // text that will no longer change
    size_t lastRunAt = 0;

    const size_t stepSamples = static_cast<size_t>(STEP_SECONDS * SAMPLE_RATE);
    const size_t maxSamples  = static_cast<size_t>(MAX_SECONDS * SAMPLE_RATE);

    while (true) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (!incoming.empty()) {
                window.insert(window.end(), incoming.begin(), incoming.end());
                incoming.clear();
            }
        }

        const bool done = finished.load();
        const bool enough = window.size() >= lastRunAt + stepSamples;

        if (!done && !enough) {
            std::this_thread::sleep_for(std::chrono::milliseconds(60));
            continue;
        }

        if (window.size() > maxSamples) {
            // Commit the older part so the next pass stays short.
            const size_t cut = findGap(window);
            std::vector<float> head(window.begin(), window.begin() + cut);
            const std::string text = transcribe(ctx, head, language, threads);
            if (!text.empty()) committed += (committed.empty() ? "" : " ") + text;
            window.erase(window.begin(), window.begin() + cut);
            lastRunAt = 0;
        }

        const std::string tail = transcribe(ctx, window, language, threads);
        lastRunAt = window.size();

        std::string whole = committed;
        if (!tail.empty()) whole += (whole.empty() ? "" : " ") + tail;

        if (done) {
            emitText("final", whole);
            break;
        }
        emitText("partial", whole);
    }

    reader.join();
    whisper_free(ctx);
    return 0;
}
