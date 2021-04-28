# frozen_string_literal: true

module PuppetStrings::Hiera
  class Data
    attr_reader :config_path, :interpolated_paths, :uninterpolated_paths, :defaults

    def initialize(config_path)
      @config_path = config_path
      @interpolated_paths = []
      # This will probably always be ['common.yaml'] jut make it an array just incase
      @uninterpolated_paths = []

      load_config
    end

    def files
      @files ||= begin
                   result = {}

                   interpolated_paths.each do |dp|
                     dp.matches.each do |file, interpolations|
                       unless result.key?(file)
                         result[file] = interpolations
                       end
                     end
                   end

                   result
                 end
    end

    # @return [Hash[String, Hash[String, Any]]]
    #   Full variable (class::var) -> filename: value
    def overrides
      @overrides ||= begin
                       overrides = {}
                       files.each_key do |file|
                         data = YAML.load(File.read(file))
                         data.each do |key, value|
                           overrides[key] ||= {}
                           overrides[key][file] = value
                         end
                       end
                       overrides
                     end
    end

    # @return [Hash[String, Hash[String, Any]]]
    #   Full variable (class::var) -> filename: value
    def defaults
      @defaults ||= begin
                      defaults = {}
                      uninterpolated_paths.each do |file|
                        data = YAML.load(File.read(file))
                        data.each do |key, value|
                          defaults[key] = value.nil? ? 'undef' : value.inspect
                        end
                      end
                      defaults
                    end
    end

    # @return [Hash[String, Hash[String, Any]]]
    #   variable -> filename: value
    def overrides_for_class(class_name)
      filter_mappings(class_name, overrides)
    end

    # @return [Hash[String, Hash[String, Any]]]
    #   variable -> filename: value
    def defaults_for_class(class_name)
      filter_mappings(class_name, defaults)
    end

    def to_s
      config_path
    end

    private

    # @return [Hash[String, Hash[String, Any]]]
    #   variable -> filename: value
    def filter_mappings(class_name, mappings)
      result = {}
      mappings.each do |key, value|
        mapped_class_name, _, variable = key.rpartition('::')
        if mapped_class_name == class_name
          result[variable] = value
        end
      end
      result
    end

    # TODO: this should be a class method not an instance method
    def load_config
      return unless File.exist?(config_path)

      config = YAML.load(File.read(config_path))

      unless config['version'] == 5
        log.warn("Unsupported version '#{config['version']}'")
        return
      end

      hierarchy = config['hierarchy']
      return unless hierarchy

      hierarchy.each do |level|
        data_hash = level['data_hash'] || config['defaults']['data_hash']
        next unless data_hash == 'yaml_data'

        datadir = level['datadir'] || config['defaults']['datadir']

        if level['path']
          if level['path'] =~ /%{[^}]+}/
            interpolated_paths << PuppetStrings::Hiera::HierarchyDataPath.new(datadir, level['path'])
          else
            uninterpolated_paths << File.join(datadir, level['path'])
          end
        elsif level['paths']
          level['paths'].each do |path|
            if path =~ /%{[^}]+}/
              interpolated_paths << PuppetStrings::Hiera::HierarchyDataPath.new(datadir, path)
            else
              uninterpolated_paths << File.join(datadir, path)
            end
          end
        end
      end
    end
  end
end
