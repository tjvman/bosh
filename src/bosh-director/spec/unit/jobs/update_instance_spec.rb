require 'spec_helper'

module Bosh::Director
  describe Jobs::UpdateInstance do
    include Support::FakeLocks

    before { fake_locks }

    let(:blobstore) { instance_double(Bosh::Blobstore::Client) }
    let(:cloud_config) { Models::Config.make(:cloud_with_manifest_v2) }
    let(:deployment) { Models::Deployment.make(name: 'simple', manifest: YAML.dump(manifest)) }
    let(:instance_state) { 'started' }
    let(:local_dns_manager) { instance_double(LocalDnsManager, update_dns_record_for_instance: nil) }
    let(:manifest) { Bosh::Spec::NewDeployments.simple_manifest_with_instance_groups }
    let(:stemcell) { Bosh::Director::Models::Stemcell.make(name: 'stemcell-name', version: '3.0.2', cid: 'sc-302') }
    let(:variables_interpolator) { ConfigServer::VariablesInterpolator.new }

    let(:delete_vm_step) { instance_double(DeploymentPlan::Steps::DeleteVmStep, perform: nil) }
    let(:detach_instance_disk_step) { instance_double(DeploymentPlan::Steps::DetachInstanceDisksStep, perform: nil) }
    let(:unmount_instance_disk_step) { instance_double(DeploymentPlan::Steps::UnmountInstanceDisksStep, perform: nil) }
    let(:vm_creator) { instance_double(VmCreator, create_for_instance_plan: nil) }
    let(:state_applier) { instance_double(InstanceUpdater::StateApplier, apply: nil) }
    let(:template_persister) { instance_double(RenderedTemplatesPersister, persist: nil) }

    let(:task) { Models::Task.make(username: 'user') }
    let(:task_writer) { TaskDBWriter.new(:event_output, task.id) }
    let(:event_log_stage) { instance_double('Bosh::Director::EventLog::Stage') }
    let(:task_manager) { instance_double(Api::TaskManager, find_task: task) }
    let(:notifier) { instance_double(DeploymentPlan::Notifier) }

    let(:instance_spec) do
      {
        'stemcell' => {
          'name' => stemcell.name,
          'version' => stemcell.version,
        },
      }
    end

    let(:instance_model) do
      instance = Models::Instance.make(
        deployment: deployment,
        job: 'foobar',
        uuid: 'test-uuid',
        index: '1',
        state: instance_state,
        spec_json: instance_spec.to_json,
      )
      Models::PersistentDisk.make(instance: instance, disk_cid: 'disk-cid')
      Models::Vm.make(instance: instance, active: true, cid: 'test-vm-cid')
      instance
    end

    let(:agent_client) do
      instance_double(
        AgentClient,
        drain: 0,
        stop: nil,
        run_script: nil,
        start: nil,
        apply: nil,
        get_state: { 'job_state' => 'running' },
      )
    end

    before do
      Models::VariableSet.make(deployment: deployment)
      deployment.add_cloud_config(cloud_config)
      release = Models::Release.make(name: 'bosh-release')
      release_version = Models::ReleaseVersion.make(version: '0.1-dev', release: release)
      template1 = Models::Template.make(name: 'foobar', release: release)
      release_version.add_template(template1)

      allow(App).to receive_message_chain(:instance, :blobstores, :blobstore).and_return(blobstore)

      allow(Api::TaskManager).to receive(:new).and_return(task_manager)
      allow(LocalDnsManager).to receive(:new).and_return(local_dns_manager)

      allow(Stopper).to receive(:stop)
      allow(VmCreator).to receive(:new).and_return(vm_creator)
      allow(RenderedTemplatesPersister).to receive(:new).and_return(template_persister)
      allow(InstanceUpdater::StateApplier).to receive(:new).and_return(state_applier)
      allow(Api::SnapshotManager).to receive(:take_snapshot)
      allow(DeploymentPlan::Steps::UnmountInstanceDisksStep).to receive(:new).and_return(unmount_instance_disk_step)
      allow(DeploymentPlan::Steps::DetachInstanceDisksStep).to receive(:new).and_return(detach_instance_disk_step)
      allow(DeploymentPlan::Steps::DeleteVmStep).to receive(:new).and_return(delete_vm_step)

      allow(Config).to receive_message_chain(:event_log, :begin_stage).and_return(event_log_stage)
      allow(event_log_stage).to receive(:advance_and_track).and_yield(nil)
      allow(Config).to receive(:record_events).and_return(true)
      allow(Config).to receive(:nats_rpc).and_return(nil)
      allow(DeploymentPlan::Notifier).to receive(:new).and_return(notifier)
      allow(notifier).to receive(:send_begin_instance_event)
      allow(notifier).to receive(:send_end_instance_event)

      allow(AgentClient).to receive(:with_agent_id).and_return(agent_client)
    end

    describe 'DelayedJob job class expectations' do
      let(:job_type) { :update_instance }
      let(:queue) { :normal }

      it_behaves_like 'a DJ job'
    end

    describe 'start' do
      let(:instance_state) { 'stopped' }

      before do
        allow(agent_client).to receive(:get_state).and_return({ 'job_state' => 'stopped' }, { 'job_state' => 'running' })
      end

      it 'should start the instance' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
        expect(instance_model.state).to eq 'stopped'
        result_msg = job.perform

        expect(state_applier).to have_received(:apply)
        expect(instance_model.reload.state).to eq 'started'
        expect(result_msg).to eq 'foobar/test-uuid'
      end

      it 'obtains a deployment lock' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
        expect(job).to receive(:with_deployment_lock).with('simple').and_yield
        job.perform
      end

      it 'logs starting' do
        expect(Config.event_log).to receive(:begin_stage)
          .with("Updating instance #{instance_model}", nil).and_return(event_log_stage)
        expect(event_log_stage).to receive(:advance_and_track).with('Starting instance').and_yield(nil)
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
        job.perform
      end

      it 'should send job templates and apply state to the VM' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
        job.perform

        expect(template_persister).to have_received(:persist).with(an_instance_of(DeploymentPlan::InstancePlanFromDB))
        expect(state_applier).to have_received(:apply)
        expect(instance_model.reload.update_completed).to eq(true)
      end

      it 'logs stopping and detaching' do
        expect(Config.event_log).to receive(:begin_stage)
          .with("Updating instance #{instance_model}", nil).and_return(event_log_stage)
        expect(event_log_stage).to receive(:advance_and_track).with('Starting instance').and_yield(nil)

        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start')

        expect(notifier).to receive(:send_begin_instance_event).with('foobar/test-uuid', 'start')
        expect(notifier).to receive(:send_end_instance_event).with('foobar/test-uuid', 'start')

        expect { job.perform }.to change { Bosh::Director::Models::Event.count }.from(0).to(2)
        expect(Bosh::Director::Models::Event.first.action).to eq 'start'
      end

      context 'when the instance is already started' do
        before do
          instance_model.update(state: 'started')
        end

        context 'and the agent reports the state as running' do
          before do
            allow(agent_client).to receive(:get_state).and_return('job_state' => 'running')
          end

          it 'does nothing' do
            job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
            expect do
              job.perform
            end.to_not(change { Models::Event.count })

            expect(state_applier).to_not have_received(:apply)
            expect(instance_model.reload.state).to eq 'started'
          end
        end

        context 'and the agent reports the state as not running' do
          it 'should start the instance' do
            job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
            job.perform

            expect(state_applier).to have_received(:apply)
            expect(instance_model.reload.state).to eq 'started'
          end
        end
      end

      context 'when the vm for the instance does not exist (due to hard stop)' do
        let(:expected_instance_plan) do
          instance_double(DeploymentPlan::InstancePlan, existing_instance: instance_model)
        end

        before do
          instance_model.active_vm.destroy
        end

        it 'requests a new vm with the right properties' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
          job.perform
          expect(vm_creator).to have_received(:create_for_instance_plan).with(
            an_instance_of(DeploymentPlan::InstancePlanFromDB),
            an_instance_of(DeploymentPlan::IpProvider),
            ['disk-cid'],
            deployment.tags,
            true,
          )
        end

        it 'should update dns records' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'start', {})
          job.perform

          expect(local_dns_manager).to have_received(:update_dns_record_for_instance)
            .with(an_instance_of(DeploymentPlan::InstancePlanFromDB))
        end
      end

      context 'when the instance does not exist' do
        it 'raises an InstanceNotFound error' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id + 10000, 'start', {})
          expect { job.perform }.to raise_error(InstanceNotFound)
        end
      end

      context 'when the instance does not belong to the deployment' do
        let(:instance_model) do
          Models::Instance.make(
            deployment: deployment,
            job: 'foobar',
            uuid: 'test-uuid',
            index: '1',
            state: 'stopped',
          )
        end
        let(:other_deployment) { Models::Deployment.make(name: 'other', manifest: YAML.dump(manifest)) }

        it 'raises an InstanceNotFound error' do
          job = Jobs::UpdateInstance.new(other_deployment.name, instance_model.id, 'start', {})
          expect { job.perform }.to raise_error(InstanceNotFound)
        end
      end
    end

    describe 'stop' do
      before do
        allow(agent_client).to receive(:get_state).and_return({ 'job_state' => 'running' }, { 'job_state' => 'stopped' })
      end

      it 'should stop the instance' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', {})
        expect(instance_model.state).to eq 'started'

        result_msg = job.perform

        expect(Stopper).to have_received(:stop).with(
          intent: :keep_vm,
          instance_plan: anything,
          target_state: 'stopped',
          logger: logger,
        )
        expect(instance_model.reload.state).to eq 'stopped'
        expect(result_msg).to eq 'foobar/test-uuid'
      end

      it 'should stop the instance and detach the VM when --hard is specified' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => true)
        expect(instance_model.state).to eq 'started'

        job.perform

        expect(Stopper).to have_received(:stop).with(
          intent: :delete_vm,
          instance_plan: anything,
          target_state: 'detached',
          logger: logger,
        )
        expect(unmount_instance_disk_step).to have_received(:perform)
        expect(detach_instance_disk_step).to have_received(:perform)
        expect(delete_vm_step).to have_received(:perform)
        expect(instance_model.reload.state).to eq 'detached'
      end

      it 'takes a snapshot of the instance' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => false)
        job.perform
        expect(Api::SnapshotManager).to have_received(:take_snapshot).with(instance_model, clean: true)
      end

      it 'obtains a deployment lock' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => false)
        expect(job).to receive(:with_deployment_lock).with('simple').and_yield
        job.perform
      end

      it 'logs stopping and detaching' do
        expect(Config.event_log).to receive(:begin_stage)
          .with("Updating instance #{instance_model}", nil).and_return(event_log_stage)
        expect(event_log_stage).to receive(:advance_and_track).with('Stopping instance').and_yield(nil)
        expect(event_log_stage).to receive(:advance_and_track).with('Deleting VM').and_yield(nil)

        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => true)

        expect(notifier).to receive(:send_begin_instance_event).with('foobar/test-uuid', 'stop')
        expect(notifier).to receive(:send_end_instance_event).with('foobar/test-uuid', 'stop')

        expect { job.perform }.to change { Bosh::Director::Models::Event.count }.from(0).to(2)
        expect(Bosh::Director::Models::Event.first.action).to eq 'stop'
      end

      context 'when detaching the VM fails in a hard stop' do
        before do
          allow(unmount_instance_disk_step).to receive(:perform).and_raise(StandardError.new('failed to detach vm'))
        end

        it 'still reports the vm as stopped' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => true)

          expect { job.perform }.to raise_error(StandardError)
          expect(instance_model.reload.state).to eq 'stopped'
        end
      end

      context 'when the instance is already soft stopped' do
        let(:instance_model) do
          Models::Instance.make(deployment: deployment, job: 'foobar', state: 'stopped', spec_json: instance_spec.to_json)
        end

        it 'detaches the vm if --hard is specified' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => true)
          job.perform

          expect(instance_model.reload.state).to eq 'detached'
        end

        it 'does nothing' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => false)
          expect do
            job.perform
          end.to_not(change { Models::Event.count })

          expect(Stopper).to_not have_received(:stop)
          expect(instance_model.reload.state).to eq 'stopped'
        end
      end

      context 'when the instance is already hard stopped' do
        let(:instance_model) { Models::Instance.make(deployment: deployment, job: 'foobar', state: 'detached') }

        it 'does nothing' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'hard' => true)
          expect do
            job.perform
          end.to_not(change { Models::Event.count })

          expect(Stopper).to_not have_received(:stop)
          expect(unmount_instance_disk_step).to_not have_received(:perform)
          expect(detach_instance_disk_step).to_not have_received(:perform)
          expect(delete_vm_step).to_not have_received(:perform)
          expect(instance_model.reload.state).to eq 'detached'
        end
      end

      context 'skip-drain' do
        before do
          allow(DeploymentPlan::InstancePlanFromDB).to receive(:create_from_instance_model).and_call_original
        end

        it 'skips drain' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'skip_drain' => true)
          job.perform

          expect(DeploymentPlan::InstancePlanFromDB).to have_received(:create_from_instance_model).with(
            instance_model,
            anything,
            'stopped',
            logger,
            'skip_drain' => true,
          )
        end
      end

      context 'when the agent is unresponsive' do
        before do
          allow(agent_client).to receive(:get_state).and_raise(Bosh::Director::RpcTimeout)
        end

        it 'ignores any unresponsive agent state if ignore-unresponsive-agent is set to true' do
          job = Jobs::UpdateInstance.new(
            deployment.name,
            instance_model.id,
            'stop',
            'ignore_unresponsive_agent' => true,
            'hard' => true,
          )
          expect { job.perform }.to_not raise_error

          expect(Stopper).to have_received(:stop)
          expect(unmount_instance_disk_step).to_not have_received(:perform)
          expect(detach_instance_disk_step).to_not have_received(:perform)
          expect(delete_vm_step).to have_received(:perform)
          expect(instance_model.reload.state).to eq 'detached'
        end

        it 'raises an error' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'stop', 'ignore_unresponsive_agent' => false)
          expect { job.perform }.to raise_error

          expect(Stopper).to_not have_received(:stop)
          expect(instance_model.reload.state).to eq 'started'
        end
      end
    end

    describe 'restart' do
      before do
        allow(agent_client).to receive(:get_state).and_return({ 'job_state' => 'running' }, { 'job_state' => 'stopped' })
      end

      it 'should restart the instance' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', {})
        result_msg = job.perform

        expect(Stopper).to have_received(:stop).with(
          intent: :keep_vm,
          instance_plan: anything,
          target_state: 'stopped',
          logger: logger,
        ).ordered
        expect(state_applier).to have_received(:apply).ordered

        expect(instance_model.reload.state).to eq 'started'
        expect(result_msg).to eq 'foobar/test-uuid'
      end

      it 'obtains a deployment lock' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', {})
        expect(job).to receive(:with_deployment_lock).with('simple').and_yield
        job.perform
      end

      it 'creates a restart event' do
        job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', {})
        expect do
          job.perform
        end.to change { Models::Event.count }.by(6)

        begin_event = Models::Event.first
        expect(begin_event.action).to eq('restart')
        expect(begin_event.parent_id).to be_nil

        end_event = Models::Event.last
        expect(end_event.action).to eq('restart')
        expect(end_event.parent_id).to eq(begin_event.id)
      end

      context 'when the option hard is set to true' do
        it 'recreates the instance' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', 'hard' => true)
          result_msg = job.perform

          expect(Stopper).to have_received(:stop).with(
            intent: :delete_vm,
            instance_plan: anything,
            target_state: 'detached',
            logger: logger,
          ).ordered
          expect(state_applier).to have_received(:apply).ordered

          expect(instance_model.reload.state).to eq 'started'
          expect(result_msg).to eq 'foobar/test-uuid'
        end

        it 'creates a recreate event' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', 'hard' => true)
          expect do
            job.perform
          end.to change { Models::Event.count }.by(6)

          begin_event = Models::Event.first
          expect(begin_event.action).to eq('recreate')
          expect(begin_event.parent_id).to be_nil

          end_event = Models::Event.last
          expect(end_event.action).to eq('recreate')
          expect(end_event.parent_id).to eq(begin_event.id)
        end
      end

      context 'skip-drain' do
        before do
          allow(DeploymentPlan::InstancePlanFromDB).to receive(:create_from_instance_model).and_call_original
        end

        it 'respects skip_drain option when constructing the instance plan' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', 'skip_drain' => true)
          job.perform

          expect(DeploymentPlan::InstancePlanFromDB).to have_received(:create_from_instance_model).with(
            instance_model,
            anything,
            'stopped',
            logger,
            'skip_drain' => true,
          ).ordered

          expect(DeploymentPlan::InstancePlanFromDB).to have_received(:create_from_instance_model).with(
            instance_model,
            anything,
            'started',
            logger,
          ).ordered
        end
      end

      context 'when starting or stopping an instance fails' do
        let(:expected_error) { 'boom' }

        before do
          allow(Stopper).to receive(:stop).and_raise
        end

        it 'raises the error' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', {})
          expect do
            job.perform
          end.to raise_error
        end

        it 'still creates the corresponding restart events' do
          job = Jobs::UpdateInstance.new(deployment.name, instance_model.id, 'restart', {})
          expect do
            expect do
              job.perform
            end.to raise_error
          end.to change { Models::Event.count }.by(4)

          begin_event = Models::Event.first
          expect(begin_event.action).to eq('restart')
          expect(begin_event.parent_id).to be_nil

          end_event = Models::Event.last
          expect(end_event.action).to eq('restart')
          expect(end_event.parent_id).to eq(begin_event.id)
          expect(end_event.error).to_not be_nil
        end
      end
    end
  end
end
