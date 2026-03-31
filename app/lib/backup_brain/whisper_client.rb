require "open3"
require "tempfile"
require "pathname"

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
      ENV["ENABLE_AUDIO_TRANSCRIPTIONS"] == "true"
    end

    # Returns true if transcription is enabled, the model file exists on disk,
    # and the whisper-cli binary can be located.
    def viable?
      self.class.enabled? && model_path.present? && File.exist?(model_path) && binary.present?
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

    private

    def model_path
      @model_path ||= begin
        raw = ENV.fetch("WHISPER_MODEL_PATH", "").strip
        return nil if raw.empty?
        path = Pathname.new(raw)
        (path.absolute? ? path : Rails.root.join(raw)).to_s
      end
    end

    def binary
      @binary ||= find_binary
    end

    def find_binary
      ["whisper-cli", "whisper-cpp"].each do |name|
        out, status = Open3.capture2("which", name)
        return out.strip if status.success? && out.strip.present?
      end
      # Homebrew fallback: binary may not be on PATH in all environments
      prefix, status = Open3.capture2("brew", "--prefix", "whisper-cpp")
      if status.success?
        candidate = File.join(prefix.strip, "bin", "whisper-cli")
        return candidate if File.executable?(candidate)
      end
      nil
    rescue
      nil
    end

    # Runs whisper-cli on +input_path+ (must be a natively supported format).
    # Uses --output-txt so the result is plain text with no timestamp formatting.
    # Returns the transcript string.
    def run_whisper(input_path)
      output_tmp = Tempfile.new("bb_whisper_out")
      output_stem = output_tmp.path
      output_tmp.close
      File.unlink(output_stem) if File.exist?(output_stem)

      _stdout, stderr, status = Open3.capture3(
        binary, "-m", model_path, "-np", "--output-txt", "-of", output_stem, input_path
      )

      txt_path = "#{output_stem}.txt"
      unless status.success? && File.exist?(txt_path)
        raise "whisper-cli failed (exit #{status.exitstatus}): #{stderr.strip}"
      end

      text = File.read(txt_path).strip
      File.unlink(txt_path)
      text
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
