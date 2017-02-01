
require_dependency Rails.root.join('app', 'models', 'verification', 'residence').to_s

class Verification::Residence

  validate :residence_present

  def residence_present
    residency_valid?
  end

  # validate :postal_code_in_castellon
  # validate :residence_in_castellon

  # def postal_code_in_castellon
  #   errors.add(:postal_code, I18n.t('verification.residence.new.error_not_allowed_postal_code')) unless valid_postal_code?
  # end

  # def residence_in_castellon
  #   return if errors.any?
  #
  #   unless residency_valid?
  #     errors.add(:residence_in_castellon, false)
  #     store_failed_attempt
  #     Lock.increase_tries(user)
  #   end
  # end

  def save
    return false unless valid?
    user.update(document_number:       document_number,
                document_type:         document_type,
                geozone:               self.geozone,
                date_of_birth:         date_of_birth.to_datetime,
                gender:                gender,
                residence_verified_at: Time.current,
                confirmed_at: Time.current,
                verified_at: Time.current)
  end

  private

    def call_census_api
      @census_api_response = PadronCastellonApi.new.call(document_type, document_number)
    end

    def residency_valid?
      @census_api_response.valid? &&
        @census_api_response.postal_code == postal_code &&
        @census_api_response.date_of_birth == date_of_birth
    end

    def valid_postal_code?
      postal_code =~ /^12/
    end

end
