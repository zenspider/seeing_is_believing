require 'seeing_is_believing/binary/interline_align'

class SeeingIsBelieving
  module Binary
    class AnnotateEveryLine
      def self.call(body, results, options)
        new(body, results, options).call
      end

      def initialize(body, results, options={})
        @options         = options
        @body            = body
        @results         = results
        @interline_align = InterlineAlign.new(results)
      end

      def call
        @new_body ||= begin
          require 'seeing_is_believing/binary/comment_lines'
          require 'seeing_is_believing/binary/format_comment'
          exception_prefix = @options[:markers][:exception][:prefix]
          value_prefix     = @options[:markers][:value][:prefix]
          exceptions       = Hash.[] @results.exceptions.map { |e| [e.line_number, e] }

          alignment_strategy = @options[:alignment_strategy].new(@body)
          new_body = CommentLines.call @body do |line, line_number|
            exception = exceptions[line_number]
            options   = @options.merge pad_to: alignment_strategy.line_length_for(line_number)
            if exception
              result = sprintf "%s: %s", exception.class_name, exception.message.gsub("\n", '\n')
              FormatComment.call(line.size, exception_prefix, result, options)
            elsif @results[line_number].any?
              if @options[:interline_align]
                result = @interline_align.call line_number, @results[line_number].map { |result| result.gsub "\n", '\n' }
              else
                result = @results[line_number].map { |result| result.gsub "\n", '\n' }.join(', ')
              end
              FormatComment.call(line.size, value_prefix, result, options)
            else
              ''
            end
          end

          require 'seeing_is_believing/binary/annotate_end_of_file'
          AnnotateEndOfFile.add_stdout_stderr_and_exceptions_to new_body, @results, @options

          new_body
        end
      end
    end
  end
end
