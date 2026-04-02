require "open3"
require "tempfile"
require "pathname"
require "json"

module BackupBrain
  class WhisperClient
    # Formats that whisper-cli accepts natively (no conversion needed).
    NATIVE_FORMATS = %w[flac mp3 ogg wav].freeze

    def self.instance
      @instance ||= new
    end

    # Force re-detection of the binary and model path (useful in development).
    def self.reload!
      @instance = new
    end

    def self.enabled?
      Setting.get_value_of_key("enable_audio_transcriptions") == true
    rescue BackupBrain::Errors::UnknownSetting
      false
    end

    # Returns true if transcription is enabled, the model file exists on disk,
    # and the whisper-cli binary can be located.
    def self.viable?
      instance.viable?
    end

    def viable?
      model_path.present? && File.exist?(model_path) && binary.present?
    end

    # Transcribes the audio file at +file_path+ and returns the transcript as a
    # plain-text string. Formats not natively supported by whisper-cli are
    # converted to 16 kHz mono WAV via ffmpeg first.
    #
    # @param file_path [String] absolute filesystem path to the audio file
    # @return [String] transcript text
    # @raise [RuntimeError] on whisper-cli or ffmpeg failure
    def transcribe(file_path)
      ext = File.extname(file_path).delete_prefix(".").downcase
      if NATIVE_FORMATS.include?(ext)
        run_whisper(file_path)
      else
        convert_and_transcribe(file_path)
      end
    end

    def model_path
      @model_path ||= begin
        raw = begin
          Setting.get_value_of_key("whisper_model_path").to_s.strip
        rescue BackupBrain::Errors::UnknownSetting
          ""
        end
        return nil if raw.empty?
        path = Pathname.new(raw)
        (path.absolute? ? path : Rails.root.join(raw)).to_s
      end
    end

    private

    def binary
      @binary ||= find_binary
    end

    def find_binary
      ["whisper-cli", "whisper-cpp"].each do |name|
        out, status = Open3.capture2("which", name)
        return out.strip if status.success? && out.strip.present?
      end
      # Homebrew fallback: check known absolute paths directly because `brew`
      # itself may not be on PATH in launchctl/systemd-started processes.
      # /opt/homebrew = Apple Silicon, /usr/local = Intel Macs.
      ["/opt/homebrew", "/usr/local"].each do |prefix|
        ["whisper-cli", "whisper-cpp"].each do |name|
          candidate = File.join(prefix, "bin", name)
          return candidate if File.executable?(candidate)
        end
      end
      nil
    rescue
      nil
    end

    # Runs whisper-cli on +input_path+ (must be a natively supported format).
    # Uses --output-json to get per-segment timestamps. Returns the transcript
    # as newline-separated lines of the form "seconds text", e.g. "42.0 Hello world."
    def run_whisper(input_path)
      output_tmp = Tempfile.new("bb_whisper_out")
      output_stem = output_tmp.path
      output_tmp.close
      File.unlink(output_stem) if File.exist?(output_stem)

      _stdout, stderr, status = Open3.capture3(
        binary, "-m", model_path, "-np", "--output-json", "-of", output_stem, input_path
      )

      json_path = "#{output_stem}.json"
      unless status.success? && File.exist?(json_path)
        raise "whisper-cli failed (exit #{status.exitstatus}): #{stderr.strip}"
      end

      data = JSON.parse(File.read(json_path))
      File.unlink(json_path)

      (data["transcription"] || []).map do |seg|
        seconds = (seg.dig("offsets", "from") || 0) / 1000.0
        text = seg["text"].to_s.strip
        "#{sprintf "%-12s", seconds.to_s} #{text}"
      end.join("\n")
    end

    # Converts +file_path+ to a 16 kHz mono WAV tempfile via ffmpeg, transcribes
    # it, then cleans up the tempfile.
    def convert_and_transcribe(file_path)
      tmp = Tempfile.new(["bb_whisper_wav", ".wav"])
      tmp.close

      _out, err, status = Open3.capture3(
        "ffmpeg", "-y", "-i", file_path,
        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
        tmp.path
      )
      unless status.success?
        tmp.unlink
        raise "ffmpeg conversion failed for transcription of #{File.basename(file_path)}: #{err.strip}"
      end

      begin
        run_whisper(tmp.path)
      ensure
        tmp.unlink
      end
    end
  end
end
