FROM ubuntu:20.04

# insert hostname on environmental variable
ENV HOSTNAME tensorflow.spark

# install prerequisites
RUN apt-get -y update
RUN apt-get -y upgrade
RUN DEBIAN_FRONTEND="noninteractive" \
    apt-get -y install tzdata \ 
        locales \
        locales-all

RUN localedef -i ko_KR -f UTF-8 ko_KR.UTF-8

ENV TZ='Asia/Seoul' \
    LANGUAGE=ko_KR.UTF-8 \
    LANG=ko_KR.UTF-8 \
    LC_ALL=ko_KR.UTF-8 \
    LC_CTYPE=ko_KR.UTF-8 \
    LC_MESSAGES=ko_KR.UTF-8

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && echo $(date +%r)

RUN apt-get -y install wget curl zip unzip vim openjdk-17-jre openjdk-17-jdk git python3 python3-pip
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# git clone tensorflowonspark.git
WORKDIR /opt/
RUN git clone --recurse-submodules https://github.com/yahoo/TensorFlowOnSpark.git

WORKDIR /opt/TensorFlowOnSpark/
RUN git submodule init
RUN git submodule update --force
RUN git submodule foreach --recursive git clean -dfx

# environmental variable for tensorflowonspark home
ENV TFoS_HOME=/opt/TensorFlowOnSpark

WORKDIR /opt/TensorFlowOnSpark/src/
RUN zip -r /opt/TensorFlowOnSpark/tfspark.zip /opt/TensorFlowOnSpark/src/*
WORKDIR /opt/TensorFlowOnSpark/

# setup spark
RUN ["/bin/bash", "-c", "source /opt/TensorFlowOnSpark/scripts/install_spark.sh"]
ENV SPARK_HOME=/opt/TensorFlowOnSpark/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}
ENV PATH=${SPARK_HOME}/bin:/opt/TensorFlowOnSpark/src:${PATH}
ENV PYTHONPATH=/opt/TensorFlowOnSpark/src

# install tensorflow, jupyter and py4j
RUN pip install pip --upgrade
RUN pip install tensorflow jupyter jupyter[notebook] py4j

# download mnist data
RUN mkdir /opt/TensorFlowOnSpark/mnist
WORKDIR /opt/TensorFlowOnSpark/mnist/
RUN curl -O "http://yann.lecun.com/exdb/mnist/train-images-idx3-ubyte.gz"
RUN curl -O "http://yann.lecun.com/exdb/mnist/train-labels-idx1-ubyte.gz"
RUN curl -O "http://yann.lecun.com/exdb/mnist/t10k-images-idx3-ubyte.gz"
RUN curl -O "http://yann.lecun.com/exdb/mnist/t10k-labels-idx1-ubyte.gz"

# create shellscript for starting spark standalone cluster
RUN echo '${SPARK_HOME}/sbin/start-master.sh' >> ${TFoS_HOME}/spark_cluster.sh
RUN echo 'MASTER=spark://${HOSTNAME}:7077' >> ${TFoS_HOME}/spark_cluster.sh
RUN echo 'SPARK_WORKER_INSTANCES=2' >> ${TFoS_HOME}/spark_cluster.sh
RUN echo 'CORES_PER_WORKER=1' >> ${TFoS_HOME}/spark_cluster.sh
RUN echo 'TOTAL_CORES=$((${CORES_PER_WORKER}*${SPARK_WORKER_INSTANCES}))' >> ${TFoS_HOME}/spark_cluster.sh
RUN echo '${SPARK_HOME}/sbin/start-slave.sh -c $CORES_PER_WORKER -m 3G ${MASTER}' >> ${TFoS_HOME}/spark_cluster.sh
RUN echo '${SPARK_HOME}/sbin/start-slave.sh -c $CORES_PER_WORKER -m 3G ${MASTER}' >> ${TFoS_HOME}/spark_cluster.sh

ENV MASTER=spark://${HOSTNAME}:7077
ENV SPARK_WORKER_INSTANCES=2
ENV CORES_PER_WORKER=1
ENV TOTAL_CORES=2

# create shellscript for pyspark on jupyter and mnist data
WORKDIR /opt/TensorFlowOnSpark/

RUN echo "PYSPARK_DRIVER_PYTHON=\"jupyter\" PYSPARK_DRIVER_PYTHON_OPTS=\"notebook --no-browser --ip=* --NotebookApp.token=''\" pyspark  --master ${MASTER} --conf spark.cores.max=${TOTAL_CORES} --conf spark.task.cpus=${CORES_PER_WORKER} --py-files ${TFoS_HOME}/tfspark.zip,${TFoS_HOME}/examples/mnist/spark/mnist_dist.py --conf spark.executorEnv.JAVA_HOME=\"$JAVA_HOME\"" > ${TFoS_HOME}/pyspark_notebook.sh

RUN echo "${SPARK_HOME}/bin/spark-submit --master ${MASTER} ${TFoS_HOME}/examples/mnist/mnist_data_setup.py --output examples/mnist/csv --format csv" > ${TFoS_HOME}/mnist_data_setup.sh

# ENTRYPOINT ["bash", "spark_cluster.sh"]
