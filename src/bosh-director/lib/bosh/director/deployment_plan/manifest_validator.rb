module Bosh
  module Director
    module DeploymentPlan
      class ManifestValidator
        def validate(manifest)
          raise_if_has_key(manifest, 'vm_types')
          raise_if_has_key(manifest, 'azs')
          raise_if_has_key(manifest, 'disk_types')
          raise_if_has_key(manifest, 'compilation')

          if manifest.key?('networks')
            raise Bosh::Director::V1DeprecatedNetworks,
                  "Deployment 'networks' are no longer supported. Network definitions must now be provided in a cloud-config."
          end

          if manifest.key?('disk_pools')
            raise Bosh::Director::V1DeprecatedDiskPools,
                  'disk_pools is no longer supported. Disk definitions must now be provided as disk_types in a cloud-config'
          end

          if manifest.key?('jobs')
            raise Bosh::Director::V1DeprecatedJob,
                  'Jobs are no longer supported, please use instance groups instead'
          end

          if manifest.key?('resource_pools')
            raise Bosh::Director::V1DeprecatedResourcePools,
                  'resource_pools is no longer supported. You must now define resources in a cloud-config'
          end

          if manifest.key?('properties')
            raise Bosh::Director::V1DeprecatedGlobalProperties,
                  "'properties' are no longer supported as a deployment level key. "\
                  "'properties' are only allowed in the 'jobs' array"
          end
        end

        private

        def raise_if_has_key(manifest, property)
          if manifest.key?(property)
            raise Bosh::Director::DeploymentInvalidProperty,
                  "Deployment manifest contains '#{property}' section, but this can only be set in a cloud-config."
          end
        end
      end
    end
  end
end
