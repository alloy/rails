require "active_record/associations/through_association_scope"

module ActiveRecord
  module Associations
    class HasManyThroughAssociation < HasManyAssociation #:nodoc:
      include ThroughAssociationScope

      alias_method :new, :build

      def create!(attrs = nil)
        transaction do
          self << (object = attrs ? @reflection.klass.send(:with_scope, :create => attrs) { @reflection.create_association! } : @reflection.create_association!)
          object
        end
      end

      def create(attrs = nil)
        transaction do
          self << (object = attrs ? @reflection.klass.send(:with_scope, :create => attrs) { @reflection.create_association } : @reflection.create_association)
          object
        end
      end

      def destroy(*records)
        transaction do
          delete_records(flatten_deeper(records))
          super
        end
      end

      # Returns the size of the collection by executing a SELECT COUNT(*) query if the collection hasn't been loaded and
      # calling collection.size if it has. If it's more likely than not that the collection does have a size larger than zero,
      # and you need to fetch that collection afterwards, it'll take one fewer SELECT query if you use #length.
      def size
        return @owner.send(:read_attribute, cached_counter_attribute_name) if has_cached_counter?
        return @target.size if loaded?
        return count
      end
      
      protected
        def target_reflection_has_associated_record?
          if @reflection.through_reflection.macro == :belongs_to && @owner[@reflection.through_reflection.primary_key_name].blank?
            false
          else
            true
          end
        end

        def construct_find_options!(options)
          options[:select]  = construct_select(options[:select])
          options[:from]  ||= construct_from
          options[:joins]   = construct_joins(options[:joins])
          options[:include] = @reflection.source_reflection.options[:include] if options[:include].nil?
        end
        
        def insert_record(record, force = true, validate = true)
          if record.new_record?
            if force
              record.save!
            else
              return false unless record.save(validate)
            end
          end
          through_reflection = @reflection.through_reflection
          klass = through_reflection.klass
          @owner.send(@reflection.through_reflection.name).proxy_target << klass.send(:with_scope, :create => construct_join_attributes(record)) { through_reflection.create_association! }
        end

        # TODO - add dependent option support
        def delete_records(records)
          klass = @reflection.through_reflection.klass
          records.each do |associate|
            klass.delete_all(construct_join_attributes(associate))
          end
        end

        def find_target
          return [] unless target_reflection_has_associated_record?
          with_scope(construct_scope) { @reflection.klass.find(:all) }
        end

        def construct_sql
          case
            when @reflection.options[:finder_sql]
              @finder_sql = interpolate_sql(@reflection.options[:finder_sql])

              @finder_sql = "#{@reflection.quoted_table_name}.#{@reflection.primary_key_name} = #{owner_quoted_id}"
              @finder_sql << " AND (#{conditions})" if conditions
            else
              @finder_sql = construct_conditions
          end

          construct_counter_sql
        end

        def has_cached_counter?
          @owner.attribute_present?(cached_counter_attribute_name)
        end

        def cached_counter_attribute_name
          "#{@reflection.name}_count"
        end

        # NOTE - not sure that we can actually cope with inverses here
        def we_can_set_the_inverse_on_this?(record)
          false
        end
    end
  end
end
