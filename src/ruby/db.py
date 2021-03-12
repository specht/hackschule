import pymysql.cursors

class mysql_connect():
    def __init__(self):
        self.connection = pymysql.connect(
            host = MYSQL_HOST,
            user = MYSQL_USER,
            password = MYSQL_PASS,
            database = MYSQL_USER,
            cursorclass = pymysql.cursors.DictCursor
        )
        
    def __enter__(self):
        return self

    def __exit__(self, type, value, traceback):
        self.connection.close()

    def query(self, query, args=None):
        with self.connection.cursor() as cursor:
            cursor.execute(query, args)
            rows = cursor.fetchall()
            return rows
              
#with connection.cursor() as cursor:
    #cursor.execute("SELECT * FROM Buch WHERE titel LIKE %s", (f"%{suchwort}%"))
    #rows = cursor.fetchall()
    #for row in rows:
        #print(f"{row['titel']}")
        
    #cursor.execute("SELECT * FROM Buch WHERE titel LIKE %s", (f"%{suchwort}%"))
    #rows = cursor.fetchall()
    #for row in rows:
        #print(f"{row['titel']}")
              
