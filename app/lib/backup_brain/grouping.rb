# BackupBrain::Grouping handles the problem of combining
# and comparing data sets that are grouped by time
# or anything else.
module BackupBrain
  module Grouping
    # Merges all the Hashes in an array & averages their values.
    #
    # By default the groups values are averaged by the number
    # of groups, but you can pass in a custom divisor.
    #
    # @param groups [Array] - an array of hashes with integer values
    # @return [Hash] - a hash with the keys from all the groups
    #   and the averaged values of each grouping.
    # @note Presumes your grouped data is a hash where the values are
    # simple integers. If a hash's key doesn't exist in the other
    # hashes the other ones will be treated as having a value of 0.
    #
    # @example merging two groups
    #  groups = [{foo: 4}, {foo: 2, bar: 4}]
    #  result = DevGood::Grouping.merge_grouped_data(groups)
    #  result # => {foo: 3, bar: 2}
    #  # foo comes from ( 4+2 / 2 ) & bar from ( 0+4 / 2 )
    def merge_grouped_data(groups, divisor = nil)
      divisor = groups.size if divisor.nil?
      new_result = {}
      groups.each do |group|
        new_result.merge!(group) { |key, initial, merging| (initial || 0) + (merging || 0) }
      end
      new_result.each do |k, v|
        new_result[k] = v / divisor
      end
      new_result
    end

    # same as merged_grouped_data but just mushes the values
    # together under the appropriate keys without alteration
    # presumes that the value of each key is an array
    # @param groups [Array[Hash]] - an array of hashes with array values
    def merge_groupings(groups, custom_sort: nil)
      raise ArgumentError, "group values must be arrays" unless groups.all? { |g| g.values.all? { |v| v.is_a? Array } }
      new_result = {}
      groups.each do |group|
        if custom_sort
          new_result.merge!(group) { |key, initial, merging|
            (initial + merging).sort(& custom_sort)
          }
        else
          new_result.merge!(group) { |key, initial, merging| initial + merging }
        end
      end
      new_result
    end

    # Given two hashes this will make sure that all the keys
    # in from_group are present in to_group. If they are
    # not present, they will be added with the default value.
    #
    # @param [Hash] from_group - the group whose keys you wish
    #   to guarantee are present in to_group
    # @param [Hash] to_group - the group whose keys need to be
    #   checked, and added to if necessary
    # @param [Integer] value - the default value to associate
    #   with missing keys.
    def add_missing_keys(from_group, to_group, value = 0)
      from_group.keys.each do |day|
        if !to_group.has_key? day
          to_group[day] = value
        end
      end
      to_group
    end

    # Builds up the grouped collections of "my" Xs by week and "their" Xs by week.
    # X is anything we normally compare by week: PRs, Reviews, Tasks, etc.
    #
    # @param since [Date] - determines how far back in time we'll look
    # @param repos [Array[Repositor]] - an array of repositories to gather associated
    #   data from
    # @param klass [Class] - any class that responds to the standard grouped_by_week method
    # @param attribute_sym [Symbol] - the name of the attribute / field whose values
    #   we should extract and group
    #
    # @return [Array[Hash, Hash]] - array of grouped values
    def generic_mine_and_theirs_by_week(since:, repos:, klass:, attribute_sym:)
      return [[], []] if repos.empty?
      me     = Person.me_me_me(repos.first.context)
      mine   = []
      theirs = []
      repos.each do |repo|
        mine.push klass.grouped_by_week(
          attribute_sym, repo, me,
          mine: true,
          since: since
        )
        theirs.push klass.grouped_by_week(
          attribute_sym, repo, me,
          mine: false,
          since: since
        )
      end
      theirs_grouped = merge_grouped_data(theirs)
      mine_grouped = merge_grouped_data(mine)
      theirs_grouped = add_missing_keys(mine_grouped, theirs_grouped)
      mine_grouped = add_missing_keys(theirs_grouped, mine_grouped)
      [mine_grouped, theirs_grouped]
    end
  end
end
