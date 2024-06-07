from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp
from pyspark.sql.types import StringType
import os

# Configurações
jdbcHostname = dbutils.secrets.get(scope="kvdataviziomvp", key="sql-host-onpremises")
jdbcPort = 1433
jdbcDatabase = "CorporeRM"
jdbcUsername = dbutils.secrets.get(scope="kvdataviziomvp", key="sql-username-onpremises")
jdbcPassword = dbutils.secrets.get(scope="kvdataviziomvp", key="sql-password-onpremises")

# Construa o URL JDBC
jdbcUrl = f"jdbc:sqlserver://{jdbcHostname}:{jdbcPort};database={jdbcDatabase}"

# Tabelas a serem extraídas
tables = ["GCCUSTO", "PPESSOA", "PFUNC", "PFUNCAO", "PSECAO"]

# Inicializa Spark
spark = SparkSession.builder.appName("IncrementalLoad").getOrCreate()

# Função para obter a última data de modificação
def get_last_timestamp():
    try:
        with open("/dbfs/mnt/incremental/last_timestamp.txt", "r") as file:
            return file.read().strip()
    except:
        return "2000-01-01 00:00:00"  # Data inicial caso não haja registros anteriores

# Função para salvar a última data de modificação
def save_last_timestamp(timestamp):
    with open("/dbfs/mnt/incremental/last_timestamp.txt", "w") as file:
        file.write(timestamp)

# Última data de execução
last_timestamp = get_last_timestamp()

# Função para extrair e salvar tabela
def extract_and_save_table(table):
    df = (spark.read.format("jdbc")
          .option("url", jdbcUrl)
          .option("dbtable", f"(SELECT * FROM dbo.{table} WHERE RECMODIFIEDON > '{last_timestamp}') AS T")
          .option("user", jdbcUsername)
          .option("password", jdbcPassword)
          .load())

    # Adiciona coluna de data de carga
    df = df.withColumn("LOAD_DATE", current_timestamp())

    # Salva no container silver
    output_path = f"abfss://silver@stdataviziomvp1717508749.dfs.core.windows.net/totvsrm/{table}.parquet"
    df.write.mode("append").parquet(output_path)

    # Atualiza a última data de modificação
    max_timestamp = df.agg({"RECMODIFIEDON": "max"}).collect()[0][0]
    if max_timestamp:
        save_last_timestamp(max_timestamp)

for table in tables:
    extract_and_save_table(table)
