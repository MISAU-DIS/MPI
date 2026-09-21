require 'swagger_helper'

RSpec.describe 'api/v1/people_details', type: :request do
  path '/v1/add_person' do
    post('Create Person Details') do
      tags 'Person'
      consumes 'application/json'
      parameter name: :person, in: :body, schema: {
        type: :object,
        properties: {
          given_name: { type: :string },
          family_name: { type: :string },
          gender: { type: :string },
          birthdate: { type: :string, format: :date },
          birthdate_estimated: { type: :boolean },
          attributes: {
            type: :object,
            properties: {
                current_district: { type: :string },
                current_traditional_authority: { type: :string },
                current_village: { type: :string },
                home_district: { type: :string },
                home_village: { type: :string },
                home_traditional_authority: { type: :string },
                occupation: { type: :string }
              }
          },
          identifiers: {
            type: :object,
            properties: {
              national_id: { type: :string }
            }
          }
        },
        required: %w[given_name family_name gender birthdate birthdate_estimated attributes home_district home_village
                     home_traditional_authority]
      }
      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/v1/search_by_name_and_gender' do
    post('search_by_name_and_gender people_detail') do
      tags 'Person'
      parameter name: :given_name, in: :query, type: :string, description: 'given_name', required: true
      parameter name: :family_name, in: :query, type: :string, description: 'family_name', required: true
      parameter name: :gender, in: :query, type: :string, description: 'gender', required: true

      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/v1/search_by_npid' do
    post('search_by_npid people_detail') do
      tags 'Person'
      parameter name: :npid, in: :query, type: :string, description: 'npid', required: true
      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/v1/search_by_doc_id' do
    post('search_by_doc_id people_detail') do
      tags 'Person'
      parameter name: :doc_id, in: :query, type: :string, description: 'doc_id', required: true
      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/v1/merge_people' do
    post('merge_people people_detail') do
      tags 'Deduplication'
      consumes 'application/json'
      parameter name: :person, in: :body, schema: {
        type: :object,
        properties: {
          primary_person_doc_id: { type: :string },
          secondary_person_doc_id: { type: :string }
        },
        required: %w[primary_person_doc_id secondary_person_doc_id]
      }

      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/v1/update_person' do
    post('update_person people_detail') do
      tags 'Person'
      consumes 'application/json'
      parameter name: :person, in: :body, schema: {
        type: :object,
        properties: {
          given_name: { type: :string },
          family_name: { type: :string },
          gender: { type: :string },
          birthdate: { type: :string, format: :date },
          birthdate_estimated: { type: :boolean },
          attributes: {
            type: :object,
            properties: {
                current_district: { type: :string },
                current_traditional_authority: { type: :string },
                current_village: { type: :string },
                home_district: { type: :string },
                home_village: { type: :string },
                home_traditional_authority: { type: :string },
                occupation: { type: :string }
              }
          },
          npid: { type: :string },
          national_id: { type: :string },
          doc_id: { type: :string }
        },
        required: %w[doc_id]
      }
      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/v1/void_person/' do
    # You'll want to customize the parameter types...
    parameter name: 'doc_id', in: :query, schema: {
      doc_id: { type: :string },
      void_reason: { type: :string }
    }

    delete('void people_detail') do
      tags 'Person'
      consumes 'application/json'
      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end

  path '/v1/mark_person_deceased/{person_uuid}' do
    parameter name: :person_uuid, in: :path, type: :string, description: 'person_uuid', required: true

    patch('mark_person_deceased people_detail') do
      tags 'Person'
      description 'Marks a person as deceased (died = true) and records the death date. ' \
                  'This is not a void: the record stays active and searchable. ' \
                  'Idempotent: calling it on an already-deceased person returns the person unchanged.'
      consumes 'application/json'
      parameter name: :deceased, in: :body, schema: {
        type: :object,
        properties: {
          deathdate: { type: :string, format: :date, description: 'Date of death (YYYY-MM-DD)' },
          deathdate_estimated: { type: :boolean, default: false, description: 'True if the date of death is an estimate' }
        },
        required: %w[deathdate]
      }

      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end

      response(400, 'deathdate is missing') do
        run_test!
      end

      response(404, 'person not found') do
        run_test!
      end
    end
  end

  path '/v1/reassign_npid' do
    post('reassign_npid people_detail') do
      tags 'Person'
      consumes 'application/json'
      parameter name: :doc_id, in: :query, type: :string, description: 'doc_id', required: true

      response(200, 'successful') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        run_test!
      end
    end
  end
end
