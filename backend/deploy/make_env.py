"""يرمّز بيانات الاتصال ويولّد هاش كلمة مرور الأدمن.

بيطبع 4 سطور: user, password, database, admin_hash
"""

import sys
from urllib.parse import quote

import bcrypt

db_user, db_pass, db_name, admin_password = sys.argv[1:5]

print(quote(db_user, safe=""))
print(quote(db_pass, safe=""))
print(quote(db_name, safe=""))
print(bcrypt.hashpw(admin_password.encode()[:72], bcrypt.gensalt()).decode())
