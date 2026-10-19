enum RoleEnum {
  patient,
  caregiver,
  forbidden;

  factory RoleEnum.fromJson(String role) {
    switch (role.toLowerCase()) {
      case "patient":
        return RoleEnum.patient;
      case 'caregiver':
        return RoleEnum.caregiver;
      case _:
        return RoleEnum.forbidden;
    }
  }
}
