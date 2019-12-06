#!/usr/bin/python3

##
# This program is open source under the BSD-3 License.
# Redistribution and use in source and binary forms, with or without modification, are permitted
# provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this list of conditions and
# the following disclaimer.
# 
# 2.Redistributions in binary form must reproduce the above copyright notice, this list of conditions
# and the following disclaimer in the documentation and/or other materials provided with the
# distribution.
#  
# 3.Neither the name of the copyright holder nor the names of its contributors may be used to endorse
# or promote products derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
##


##########################
# Service: HSNmon 
# Script: send_to_rmq.py
# Usage: Reads from stdin and sends it to RabbitMQ 
##########################


import sys
import os
import argparse
import yaml
import pika
import ssl
import pdb
import time
import logging
from logging.handlers import RotatingFileHandler


class ConfigurationError(Exception):
    """ Exception class for config errors
    """
    def __init__(self, value):
        self.value = value
    def __str__(self):
        return repr(self.value)


def main():

    parser = argparse.ArgumentParser(
        description='General purpose tool for sending data via AMQP.')
    parser.add_argument("--send_file", help='define a file to be sent as a single message')
    parser.add_argument("--file_header", help='add a header string that is sent before the file data', default='')
    parser.add_argument("--file_footer", help='add a footer string that is sent after the file data', default='')
    parser.add_argument("--buf_size", help='buffer size to use for reading/writing', default=4096, type=int)
    parser.add_argument("--debug_file", help='file to write debugging logs to')
    required = parser.add_argument_group("required named arguments")
    required.add_argument("--config", help='define the config file location', required=True)
    args = parser.parse_args()
    if (args.file_footer or args.file_header) and not args.send_file:
        sys.stderr.write("must specify a file to send via --send_file if you want to add a header or footer to the file\n")
        sys.exit(1)

    # load the config from the file and get all values under the "CONFIG" key
    config = yaml.safe_load(open(args.config))["CONFIG"]

    # set the parameters
    parameters = set_params(config)

    logger = get_logger(args.debug_file)

    # stream mode
    if not args.send_file:
        send_stdin(config, parameters, args, logger)
    # file mode
    else:
        send_file(config, parameters, args, logger)


def set_params(config):

    # default to cert-based auth
    if "CACERT_PATH" in config and "CERTFILE_PATH" in config and "KEYFILE_PATH" in config:

        sslOptions = {
         "cert_reqs": ssl.CERT_REQUIRED,
         "ca_certs": config["CACERT_PATH"],
         "certfile": config["CERTFILE_PATH"],
         "keyfile": config["KEYFILE_PATH"],
         "server_side": False 
        }

        credentials = pika.credentials.ExternalCredentials()

        # set connection parameters 
        parameters = pika.ConnectionParameters(
            host = config["HOST"],
            virtual_host = config["VIRTUALHOST"],
            port = int(config["PORT"]),
            credentials = credentials,
            ssl = True,
            ssl_options = sslOptions)

    # password based auth still supported
    elif "PASSWORD" in config and "USERNAME" in config:

        credentials = pika.PlainCredentials(config["USERNAME"],config["PASSWORD"])

        # set connection parameters 
        parameters = pika.ConnectionParameters(
            host = config["HOST"],
            virtual_host = config["VIRTUALHOST"],
            port = int(config["PORT"]),
            credentials = credentials)
    else:
        raise ConfigurationError("Valid authentication config values not found in {} "
            "Must include valid CACERT_PATH, CERTFILE_PATH, and KEYFILE_PATH values "
            "or valid USERNAME and PASSWORD values".format(args.config))
    return parameters


def get_logger(path):
    if not path:
        return None
    logger = logging.getLogger(__file__)
    logger.setLevel(logging.INFO)
    handler = RotatingFileHandler(path, maxBytes=65536, backupCount=5)
    logger.addHandler(handler)
    return logger


def send_file(config, parameters, args, logger):

    # set up connection 
    connection = pika.BlockingConnection(parameters)
    channel = connection.channel()

    # send file as one contiguous AMQP message
    with open(args.send_file, 'rb') as f:
        send_str = ''
        file_str = f.read()
        send_str = (''.join([args.file_header, file_str, args.file_footer]) if args.file_header or args.file_footer else file_str)

        # send message to rmq
        delivered = channel.basic_publish( \
            config["EXCHANGE"], config["ROUTINGKEY"], send_str, \
            pika.BasicProperties(delivery_mode=1))
    # close connection
    connection.close()


def send_stdin(config, parameters, args, logger):

    # set up connection 
    while(True):
        try:
            connection = pika.BlockingConnection(parameters)
            channel = connection.channel()

            # get message fr/stdin
            #message = sys.stdin.readline()
            message = os.read(0, args.buf_size)
            if(not message):
                raise EOFError
            elif(debug):
                print(message)
                continue
            # send message to rmq
            delivered = channel.basic_publish( \
                config["EXCHANGE"], config["ROUTINGKEY"], message, \
                pika.BasicProperties(delivery_mode=1))

            if(not delivered):
                print("message not delivered: {}".format(message))

        # done reading from stdin
        except EOFError:
            break
        except ConfigurationError as e:
            raise e


        # in case RabbitMQ closes the connection
        except Exception as e:
            connection.close()
            ex = "[{}]\n{}".format(type(e).__name__,str(e))
            print(ex)
            if logger:
                logger.info(ex)
            time.sleep(1)
            continue


    # close connection
    connection.close()


if __name__ == "__main__":
    try:
        debug = False
        main()
    except KeyboardInterrupt:
        sys.exit(0)
    except EOFError:
        pass
        

