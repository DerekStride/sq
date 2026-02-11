# frozen_string_literal: true

module App
  class User
    attr_reader :id, :name, :email, :role

    VALID_ROLES = %w[admin editor viewer].freeze

    def initialize(id:, name:, email:, role: "viewer")
      @id = id
      @name = name
      @email = email
      @role = role
      validate!
    end

    def admin?
      role == "admin"
    end

    def can_edit?
      %w[admin editor].include?(role)
    end

    def to_h
      { id: id, name: name, email: email, role: role }
    end

    private

    def validate!
      raise ArgumentError, "Invalid role: #{role}" unless VALID_ROLES.include?(role)
      raise ArgumentError, "Email required" if email.nil? || email.empty?
    end
  end
end
