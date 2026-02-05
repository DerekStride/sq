# frozen_string_literal: true

require "open3"
require "json"

module Sift
  module Roast
    # Orchestrates Roast workflow execution with Sift queue integration
    class Orchestrator
      class ExecutionError < Error; end

      attr_reader :workflow, :queue, :revision_workflow

      # Initialize the orchestrator
      #
      # @param workflow [String] path to main workflow.rb
      # @param queue [Sift::Queue] queue instance for results
      # @param revision_workflow [String, nil] path to revision workflow (optional)
      def initialize(workflow:, queue:, revision_workflow: nil)
        @workflow = workflow
        @queue = queue
        @revision_workflow = revision_workflow

        validate_workflow!(workflow)
        validate_workflow!(revision_workflow) if revision_workflow
      end

      # Run the workflow with targets
      #
      # Executes: roast execute workflow.rb target1 target2 -- key=value
      # The workflow should use the sift_output cog to push results
      #
      # @param targets [Array<String>] list of targets to process
      # @param kwargs [Hash] additional keyword arguments passed to workflow
      # @return [Hash] execution result with :success, :stdout, :stderr, :status
      def run(targets:, **kwargs)
        execute_workflow(@workflow, targets: targets, **kwargs)
      end

      # Run revision workflow with feedback
      #
      # @param item_id [String] ID of the item to revise
      # @param feedback [String] feedback for revision
      # @return [Hash, nil] execution result or nil if no revision_workflow configured
      def revise(item_id:, feedback:)
        return nil unless @revision_workflow

        item = @queue.find(item_id)
        raise Error, "Item not found: #{item_id}" unless item

        # Extract original metadata and pass to revision workflow
        original_metadata = item.metadata || {}
        original_target = original_metadata["target"] || original_metadata[:target]

        targets = original_target ? [original_target] : []

        execute_workflow(
          @revision_workflow,
          targets: targets,
          original_item_id: item_id,
          original_metadata: original_metadata.to_json,
          feedback: feedback
        )
      end

      private

      def validate_workflow!(path)
        return if File.exist?(path)

        raise Error, "Workflow not found: #{path}"
      end

      def execute_workflow(workflow_path, targets:, **kwargs)
        cmd = build_command(workflow_path, targets, kwargs)
        env = build_env

        stdout, stderr, status = Open3.capture3(env, *cmd)

        result = {
          success: status.success?,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus
        }

        unless status.success?
          raise ExecutionError, "Workflow failed (exit #{status.exitstatus}): #{stderr}"
        end

        result
      end

      def build_command(workflow_path, targets, kwargs)
        cmd = ["bundle", "exec", "roast", "execute", workflow_path]
        cmd.concat(targets) if targets.any?

        if kwargs.any?
          cmd << "--"
          kwargs.each do |key, value|
            cmd << "#{key}=#{value}"
          end
        end

        cmd
      end

      def build_env
        {
          QUEUE_PATH_ENV => @queue.path
        }
      end
    end
  end
end
