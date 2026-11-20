from pymongo import MongoClient

try:
    client = MongoClient("mongodb://localhost:27017/", serverSelectionTimeoutMS=5000)
    client.server_info()
    print("MongoDB connected successfully")

    db = client["roadresq_db"]
    collection = db["test_collection"]

    result = collection.insert_one({"message": "connection successful"})
    print("Inserted ID:", result.inserted_id)

except Exception as e:
    print("MongoDB connection failed:")
    print(e)