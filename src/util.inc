macro align(size) {
  while (pc() % {size}) {
    db 0
  }
}

macro db_array(size) {
	variable count = {size}
	while count > 0 {
		db 0
		count = count - 1
	}
}