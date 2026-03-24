# frozen_string_literal: true

require 'syncing_service/sync_service'

module Api
  module V1
    # Synchronization service
    class SyncController < ApplicationController
      before_action :validate_pull_source, only: %i[pull_updates_new pull_updates pull_npids]
      before_action :validate_push_source, only: %i[pushed_updates_new pushed_updates]
      before_action :validate_foot_print_source, only: [:pushed_footprints]
      after_action :update_movement_cache, only: [:pushed_footprints]

      def pull_updates_new
        records_changed = SyncService.person_changes_new(update_params)

        render json: records_changed
      end

      def pull_updates
        records_changed = SyncService.person_changes_updates(update_params)

        render json: records_changed
      end

      def pushed_updates
        update = SyncService.update_records_updates(push_params)
        if update
          render json: update, status: :created
        else
          render json: { msg: 'Something went wrong' }, status: :internal_server_error
        end
      end

      def pushed_updates_new
        update = SyncService.update_records_new(push_params)
        if update
          render json: update, status: :created
        else
          render json: { msg: 'Something went wrong' }, status: :unprocessable_entity
        end
      end

      def pull_npids
        npids = SyncService.pull_npids(npid_params)
        render json: npids
      end

      def pushed_footprints
        footprints = SyncService.save_footprint(foot_print_params)
        if footprints.errors.any?
          render json: { msg: 'Something went wrong' }, status: :internal_server_error
        else
          render json: footprints, status: :created
        end
      end

      def pushed_errors
        error = SyncService.save_errors(error_params)
        if error.errors.any?
          render json: { msg: 'Something went wrong' }, status: :internal_server_error
        else
          render json: error, status: :created
        end
      end

      def sync_errors
        sync_errors = SyncService.sync_errors

        if sync_errors.blank?
          render json: {}, status: :not_found
        else
          render json: sync_errors, status: :ok
        end
      end

      private

      def update_params
        params.require(%i[site_id pull_seq])
      end

      def npid_params
        params.require(%i[site_id npid_seq])
        { site_id: params[:site_id], npid_seq: params[:npid_seq] }
      end

      def push_params
        params.permit(:id,
                      :last_name,
                      :first_name,
                      :middle_name,
                      :gender,
                      :current_village,
                      :current_traditional_authority,
                      :current_district,
                      :home_village,
                      :home_traditional_authority,
                      :home_district,
                      :provincia,
                      :distrito,
                      :bairro,
                      :localidade,
                      :ponto_de_referencia,
                      :birthdate,
                      :birthdate_estimated,
                      :person_uuid,
                      :npid,
                      :national_id,
                      :date_registered,
                      :last_edited,
                      :location_created_at,
                      :location_updated_at,
                      :creator,
                      :home_ta,
                      :ancestry_village,
                      :ancestry_ta,
                      :ancestry_district,
                      :voided,
                      :voided_by,
                      :date_voided,
                      :void_reason,
                      :first_name_soundex,
                      :last_name_soundex,
                      :update_seq,
                      person_identifiers: [:type, :value])
      end

      def validate_pull_source
        if params[:site_id].to_i != begin
          Location.find_by_ip_address(request.remote_ip).location_id
        rescue StandardError
          nil
        end
          render json: { msg: 'Request source cannot be verified please contact Admin' },
                 status: :network_authentication_required
        end
      end

      def validate_push_source
        if params[:location_updated_at].to_i != begin
          Location.find_by_ip_address(request.remote_ip).location_id
        rescue StandardError
          nil
        end
          render json: { msg: 'Request source cannot be verified please contact Admin' },
                 status: :network_authentication_required
        end
      end

      def validate_foot_print_source
        if params[:location_id].to_i != begin
          Location.find_by_ip_address(request.remote_ip).location_id
        rescue StandardError
          nil
        end
          render json: { msg: 'Request source cannot be verified please contact Admin' },
                 status: :network_authentication_required
        end
      end

      def foot_print_params
        params.require(%i[user_id person_uuid program_id location_id uuid encounter_datetime created_at updated_at])
        params.permit(:user_id, :person_uuid, :program_id, :location_id, :uuid, :encounter_datetime, :created_at,
                      :updated_at)

        { user_id: params[:user_id], person_uuid: params[:person_uuid], encounter_datetime: params[:encounter_datetime],
          program_id: params[:program_id], location_id: params[:location_id], uuid: params[:uuid],
          app_date_created: params[:created_at], app_date_updated: params[:updated_at] }
      end

      def error_params
        params.permit(:site_id, :incident_time, :error, :synced, :uuid, :created_at, :updated_at)
      end

      def send_mail
        LowNpidNotificationJob.perform_later(params[:location_updated_at].to_i)
        LastSeenLastSyncedJob.perform_later
      end

      def update_movement_cache
        person_uuid = foot_print_params[:person_uuid]
        UpdateMovementJob.perform_later(person_uuid)
      end
    end
  end
end
