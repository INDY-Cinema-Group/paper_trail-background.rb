# frozen_string_literal: true

module PaperTrail
  module Background
    # Versions are written by background jobs, so a version's primary key
    # reflects the order the jobs ran in, not the order the changes happened.
    # `created_at` is stamped when the change happens, so it is the
    # authoritative order.
    #
    # PaperTrail navigates by primary key whenever the key is an integer. These
    # modules make that navigation use `created_at` instead, with the primary
    # key as a tie-breaker (as `timestamp_sort_order` already does for the
    # `versions` association).
    module Ordering
      # Class-level scopes behind `Version#previous` and `Version#next`, and so
      # behind `previous_version` and `next_version` on a reified record.
      module VersionScopes
        # Versions before `obj`. When `obj` is a version, "before" means an
        # earlier `created_at`, or the same `created_at` and a smaller id.
        def preceding(obj, timestamp_arg = false)
          return super unless chronological_navigation?(obj, timestamp_arg)

          where(
            arel_table[:created_at].lt(obj.created_at).or(
              arel_table[:created_at].eq(obj.created_at).and(arel_table[primary_key].lt(obj.id))
            )
          ).order(timestamp_sort_order("desc"))
        end

        # Versions after `obj`. See `preceding`.
        def subsequent(obj, timestamp_arg = false)
          return super unless chronological_navigation?(obj, timestamp_arg)

          where(
            arel_table[:created_at].gt(obj.created_at).or(
              arel_table[:created_at].eq(obj.created_at).and(arel_table[primary_key].gt(obj.id))
            )
          ).order(timestamp_sort_order("asc"))
        end

        private

        # Only a version with a `created_at` can be placed by timestamp. A raw
        # timestamp (`timestamp_arg == true`) is already handled by PaperTrail.
        def chronological_navigation?(obj, timestamp_arg)
          timestamp_arg != true && obj.is_a?(self) && !obj.created_at.nil?
        end
      end

      # The ordered list behind `Version#index`.
      module HistorySequence
        private

        # Always chronological, whatever the primary key type.
        def sequence
          @versions.
            select([table[:created_at], primary_key]).
            order(@version_class.timestamp_sort_order)
        end
      end
    end
  end
end

PaperTrail::VersionConcern::ClassMethods.prepend(PaperTrail::Background::Ordering::VersionScopes)
PaperTrail::RecordHistory.prepend(PaperTrail::Background::Ordering::HistorySequence)
