require 'seeing_is_believing/parser_helpers'

class SeeingIsBelieving
  class Binary
    class CommentableLines

      include ParserHelpers

      def self.call(code)
        new(code).call
      end

      def initialize(code)
        self.code = code
        self.buffer, self.parser, self.rewriter, self.root, self.comments =
          initialize_parser(code, 'strip_comments')
      end

      def call
        @call ||= begin
          line_num_to_indexes = line_nums_to_last_index_and_col(buffer)
          remove_lines_after_data_segment           line_num_to_indexes
          remove_lines_whose_newline_is_escaped     line_num_to_indexes
          remove_lines_ending_in_comments           line_num_to_indexes, comments
          remove_lines_inside_of_strings_and_things line_num_to_indexes, root
          line_num_to_indexes
        end
      end

      attr_reader :buffer, :rewriter

      private

      attr_writer :buffer, :rewriter
      attr_accessor :code, :parser, :root, :comments

      def line_nums_to_last_index_and_col(buffer)
        line_num_to_indexes = code.each_char
                                  .with_index
                                  .select { |char, index| char == "\n" } # <-- is this okay? what about other OSes?
                                  .each_with_object(Hash.new) do |(_, index), hash|
                                    line, col = buffer.decompose_position index
                                    hash[line] = [index, col]
                                  end
        if code[code.size-1] != "\n" # account for the fact that the last line wouldn't have been found above if it doesn't end in a newline
          line, col = buffer.decompose_position code.size
          line_num_to_indexes[line] = [code.size, col]
        end
        line_num_to_indexes
      end

      def remove_lines_whose_newline_is_escaped(line_num_to_indexes)
        line_num_to_indexes.select { |line_number, (index_of_newline, col)| code[index_of_newline-1] == '\\' }
                           .each   { |line_number, (index_of_newline, col)| line_num_to_indexes.delete line_number }
      end

      def remove_lines_ending_in_comments(line_num_to_indexes, comments)
        comments.each do |comment|
          if comment.type == :inline
            line_num_to_indexes.delete comment.location.line
          else
            begin_pos = comment.location.expression.begin_pos
            end_pos   = comment.location.expression.end_pos
            range     = begin_pos...end_pos
            line_num_to_indexes.select { |line_number, (index_of_newline, col)| range.include? index_of_newline }
                               .each   { |line_number, (index_of_newline, col)| line_num_to_indexes.delete line_number }
          end
        end
      end

      def remove_lines_inside_of_strings_and_things(line_num_to_indexes, ast)
        invalid_boundaries = ranges_of_atomic_expressions ast, []
        invalid_boundaries.each do |invalid_boundary|
          line_num_to_indexes.select { |line_number, (index_of_newline, col)| invalid_boundary.include? index_of_newline }
                             .each   { |line_number, (index_of_newline, col)| line_num_to_indexes.delete line_number }
        end
      end

      def ranges_of_atomic_expressions(ast, found_ranges)
        return found_ranges unless ast.kind_of? ::AST::Node
        if no_comment_zone?(ast) && heredoc?(ast)
          begin_pos  = ast.location.expression.begin.begin_pos
          begin_pos += (ast.location.expression.source =~ /\n/).next
          end_pos    = ast.location.expression.end.end_pos.next
          found_ranges << (begin_pos...end_pos)
        elsif no_comment_zone? ast
          begin_pos = ast.location.expression.begin.begin_pos
          end_pos   = ast.location.expression.end.end_pos
          found_ranges << (begin_pos...end_pos)
        else
          ast.children.each { |child| ranges_of_atomic_expressions child, found_ranges }
        end
        found_ranges
      end

      def no_comment_zone?(ast)
        case ast.type
        when :dstr, :str, :xstr, :regexp
          true
        when :array
          the_begin = ast.location.begin
          the_begin && the_begin.source =~ /\A%/
        else
          false
        end
      end

      def remove_lines_after_data_segment(line_num_to_indexes)
        data_segment_line, _ = line_num_to_indexes.find do |line_number, (end_index, col)|
          if end_index == 7
            code.start_with? '__END__'
          elsif end_index < 7
            false
          else
            code[(end_index-8)...end_index] == "\n__END__"
          end
        end
        return unless data_segment_line
        max_line = line_num_to_indexes.keys.max
        data_segment_line.upto(max_line) { |line_number| line_num_to_indexes.delete line_number }
      end
    end
  end
end