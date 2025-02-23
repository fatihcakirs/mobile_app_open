# Copyright (c) 2020-2021 Qualcomm Innovation Center, Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

# This file must be called from top level Makefile

include ../make/builddir.mk

all: ${BUILDDIR}/datasets.stamp hta-dlc htp-dlc

.PHONY: hta-dlc htp-dlc dependencies gen-hta-dlc-info gen-htp-dlc-info clean

include ../make/docker.mk

DLCBUILDDIR=${BUILDDIR}/DLC
MODEL_BASE_PATH=${BUILDDIR}/mobile
MOBILENETEDGETPU_MODEL_PATH=${MODEL_BASE_PATH}/vision/mobilenet/models_and_code/checkpoints/float
DEEPLABV3QAT_MODEL_PATH=${MODEL_BASE_PATH}/vision/deeplab/models_and_code/checkpoints/quantize_aware_training
MOBILEBERT_MODEL_PATH=${MODEL_BASE_PATH}/language/bert/models_and_code/checkpoints/quant/

hta-dlc: ${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_hta.stamp \
	${DLCBUILDDIR}/ssd_mobiledet_qat_hta.stamp \
	${DLCBUILDDIR}/deeplabv3_hta.stamp

htp-dlc: ${DLCBUILDDIR}/mobilebert_htp.stamp \
	${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_htp.stamp \
	${DLCBUILDDIR}/ssd_mobiledet_qat_htp.stamp \
	${DLCBUILDDIR}/deeplabv3_htp.stamp \
	${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_htp_batched.stamp

mobilenet_edgetpu: \
	${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_htp.stamp \
	${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_hta.stamp

mobiledet: \
	${DLCBUILDDIR}/ssd_mobiledet_qat_hta.stamp \
	${DLCBUILDDIR}/ssd_mobiledet_qat_htp.stamp

deeplabv3: \
	${DLCBUILDDIR}/deeplabv3_htp.stamp \
	${DLCBUILDDIR}/deeplabv3_hta.stamp

mobilebert: \
	${DLCBUILDDIR}/mobilebert_htp.stamp

${BUILDDIR}/datasets.stamp:
	@(cd ../datasets && make)
	@touch $@

${BUILDDIR}/mobile/.stamp:
	@curl -H  "Authorization: token ${GITHUB_TOKEN}" -o ${BUILDDIR}/mobile.zip -L https://github.com/mlcommons/mobile/archive/mobiledet-export_inference_graph.zip
	@cd ${BUILDDIR} && unzip mobile.zip
	@mv ${BUILDDIR}/mobile-mobiledet-export_inference_graph ${BUILDDIR}/mobile
	@touch $@

${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_float.dlc: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${BUILDDIR}/mobile/.stamp
	@echo "Mobilenetedge TPU model conversion ...."
	@echo "Float model"
	@mkdir -p ${DLCBUILDDIR}
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${MOBILENETEDGETPU_MODEL_PATH}:/models \
		-v ${DLCBUILDDIR}:/output \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c '/snpe_sdk/bin/x86_64-linux-clang/snpe-tensorflow-to-dlc \
			-i /models/frozen_graph_tf1x_transform.pb \
			-d input "1,224,224,3" --out_node "MobilenetEdgeTPU/Predictions/Softmax" \
			-o /output/mobilenet_edgetpu_224_1.0_float.dlc'

${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_hta.stamp: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_float.dlc
	@echo "Quantization of MobilenetEdgeTPU DLC for HTA"
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${BUILDDIR}/imagenet/imagenet_out:/imagenet-out \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c "cd /imagenet-out && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/mobilenet_edgetpu_224_1.0_float.dlc \
			--input_list=/imagenet-out/imagenet_image_list.txt \
			--output_dlc=/output/mobilenet_edgetpu_224_1.0_hta.dlc \
			--enable_hta"
	@echo "Mobilenetedge TPU model conversion completed"
	@touch $@

${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_htp.stamp: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_float.dlc
	@echo "Quantization of MobilenetEdgeTPU DLC for HTP"
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${BUILDDIR}/imagenet/imagenet_out:/imagenet-out \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c "cd /imagenet-out && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/mobilenet_edgetpu_224_1.0_float.dlc \
			--input_list=/imagenet-out/imagenet_image_list.txt \
			--output_dlc=/output/mobilenet_edgetpu_224_1.0_htp.dlc \
			--enable_htp \
			--htp_socs sm8350,sm7325"
	@echo "Mobilenetedge TPU model conversion completed"
	@touch $@

${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_float_batched.dlc: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${BUILDDIR}/mobile/.stamp
	@echo "Mobilenetedge TPU model conversion ...."
	@echo "Batched Float model"
	@mkdir -p ${DLCBUILDDIR}
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${MOBILENETEDGETPU_MODEL_PATH}:/models \
		-v ${DLCBUILDDIR}:/output \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c '/snpe_sdk/bin/x86_64-linux-clang/snpe-tensorflow-to-dlc \
			-i /models/frozen_graph_tf1x_transform.pb \
			-d input "4,224,224,3" --out_node "MobilenetEdgeTPU/Predictions/Softmax" \
			-o /output/mobilenet_edgetpu_224_1.0_float_batched.dlc'

${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_htp_batched.stamp: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${DLCBUILDDIR}/mobilenet_edgetpu_224_1.0_float_batched.dlc
	@echo "Quantization of MobilenetEdgeTPU Batched DLC for HTP"
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${BUILDDIR}/imagenet/imagenet_out:/imagenet-out \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c "cd /imagenet-out && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/mobilenet_edgetpu_224_1.0_float_batched.dlc \
			--input_list=/imagenet-out/imagenet_image_list.txt \
			--output_dlc=/output/mobilenet_edgetpu_224_1.0_htp_batched.dlc \
			--enable_htp \
			--htp_socs sm8350,sm7325"
	@echo "Mobilenetedge TPU model conversion completed"
	@touch $@
	
${DLCBUILDDIR}/ssd_mobiledet_qat.dlc: \
		${BUILDDIR}/mobile/.stamp
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/dlc \
		-v ${BUILDDIR}/mobile/vision/mobiledet/uint8/export_inference_graph:/model \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c '/snpe_sdk/bin/x86_64-linux-clang/snpe-tensorflow-to-dlc \
			-i model/frozen_inference_graph.pb \
			-d Preprocessor/map/TensorArrayStack/TensorArrayGatherV3 "1,320,320,3" \
			--out_node "detection_classes" \
			--out_node "detection_boxes" \
			--out_node "detection_scores" \
			-o /dlc/ssd_mobiledet_qat.dlc'
		
${DLCBUILDDIR}/ssd_mobiledet_qat_hta.stamp: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${BUILDDIR}/mobile/.stamp \
		${DLCBUILDDIR}/ssd_mobiledet_qat.dlc
	@echo "Quantization of MobileDET SSD DLC for HTA"
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${BUILDDIR}/coco/coco_out:/coco-out \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c "cd /coco-out && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/ssd_mobiledet_qat.dlc \
			--input_list=/coco-out/coco_image_list.txt \
			--output_dlc=/output/ssd_mobiledet_qat_hta.dlc \
			--enable_hta --hta_partitions sm8250"
	@echo "SSD MobileDET model conversion for HTA completed"
	@touch $@

${DLCBUILDDIR}/ssd_mobiledet_qat_htp.stamp: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${BUILDDIR}/mobile/.stamp \
		${DLCBUILDDIR}/ssd_mobiledet_qat.dlc
	@echo "Quantization of MobileDET SSD DLC for HTP"
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${MOBILEDETSSDQAT_MODEL_PATH}:/models \
		-v ${DLCBUILDDIR}:/output \
		-v ${BUILDDIR}/coco/coco_out:/coco-out \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c "cd /coco-out && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/ssd_mobiledet_qat.dlc \
			--input_list=/coco-out/coco_image_list.txt \
			--output_dlc=/output/ssd_mobiledet_qat_htp.dlc \
			--enable_htp \
			--htp_socs sm8350,sm7325"
	@echo "SSD MobileDET model conversion for HTP completed"
	@touch $@


${DLCBUILDDIR}/deeplabv3_quantized.dlc: ${TOPDIR}/DLC/argmax-quant.json ${DEEPLABV3QAT_MODEL_PATH}/freeze.pb \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${BUILDDIR}/mobile/.stamp
	@echo "Deeplab v3 model conversion ...."
	@echo "Deeplabv3 QAT model"
	@cat ${TOPDIR}/DLC/argmax-quant.json
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DEEPLABV3QAT_MODEL_PATH}:/deeplabv3 \
		-v ${DLCBUILDDIR}:/output \
		-v ${TOPDIR}/DLC:/dlc \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c '/snpe_sdk/bin/x86_64-linux-clang/snpe-tensorflow-to-dlc \
			-i /deeplabv3/freeze.pb \
			-d ImageTensor "1,512,512,3" \
			--out_node ArgMax \
			--quantization_overrides /dlc/argmax-quant.json \
			-o /output/deeplabv3_quantized.dlc'
	@echo "Generated DLC from Deeplabv3 QAT model"


${DLCBUILDDIR}/deeplabv3_hta.stamp: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${DLCBUILDDIR}/deeplabv3_quantized.dlc
	@echo "Quantization of Deeplabv3 DLC"
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${BUILDDIR}/ade20k/ade20k_out:/ade20k-out \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c 'cd /ade20k-out/ && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/deeplabv3_quantized.dlc \
			--input_list=/ade20k-out/ade20k_image_list.txt \
			--output_dlc=/output/deeplabv3_hta.dlc \
			--enable_hta'
	@echo "Deeplab v3 model conversion completed"
	@# Can't use deeplabv3_hta.dlc as make target since this file is present on failure
	@touch $@

${DLCBUILDDIR}/deeplabv3_htp.stamp: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${DLCBUILDDIR}/deeplabv3_quantized.dlc
	@echo "Quantization of Deeplabv3 DLC"
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${BUILDDIR}/ade20k/ade20k_out:/ade20k-out \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c 'cd /ade20k-out/ && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/deeplabv3_quantized.dlc \
			--input_list=/ade20k-out/ade20k_image_list.txt \
			--output_dlc=/output/deeplabv3_htp.dlc \
			--override_params --enable_htp \
			--htp_socs sm8350,sm7325'
	@echo "Deeplab v3 model conversion completed"
	@# Can't use deeplabv3_htp.dlc as make target since this file is present on failure
	@touch $@

${DLCBUILDDIR}/mobilebert_quant.pb: ${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		${BUILDDIR}/mobile/.stamp
	@echo "MobileBERT quant model freeze ...."
	@mkdir -p ${DLCBUILDDIR}
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${MOBILEBERT_MODEL_PATH}:/models \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		python3 /usr/local/lib/python3.6/dist-packages/tensorflow_core/python/tools/freeze_graph.py \
			--input_graph=/models/saved_model.pb --input_checkpoint=/models/checkpoints/quant \
			--output_graph=/output/mobilebert_quant.pb \
			--output_node_names=end_logits,start_logits \
			--input_binary= True \
			--input_saved_model_dir=/models/ saved_model_tags="serve"

${DLCBUILDDIR}/mobilebert_float.dlc:${DLCBUILDDIR}/mobilebert_quant.pb \
									${BUILDDIR}/mlperf_mobile_docker_1_0.stamp \
									${BUILDDIR}/datasets.stamp \
									${BUILDDIR}/mobile/.stamp
	@echo "MobileBERT tf to DLC conversion"
	@mkdir -p ${DLCBUILDDIR}
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/output \
		-v ${TOPDIR}/DLC:/dlc \
		-v ${MOBILEBERT_MODEL_PATH}:/models \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c '/snpe_sdk/bin/x86_64-linux-clang/snpe-tensorflow-to-dlc \
			--input_network /output/mobilebert_quant.pb \
			--input_dim bert/embeddings/ExpandDims 1,384,1 \
			--input_dim input_mask 1,384 \
			--input_dim segment_ids 1,384 \
			--input_type bert/embeddings/ExpandDims opaque \
			--input_type input_mask default \
			--input_type segment_ids opaque \
			--out_node transpose \
			-o /output/mobilebert_float.dlc'
	@echo "MobileBERT Float DLC conversion completed"


${DLCBUILDDIR}/mobilebert_htp.stamp: ${DLCBUILDDIR}/mobilebert_float.dlc \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp \
		${BUILDDIR}/datasets.stamp
	@echo "MobileBERT float model quantization ..."
	@mkdir -p ${DLCBUILDDIR}
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${BUILDDIR}/SQUAD/SQUAD_out:/squad-out \
		-v ${DLCBUILDDIR}:/output \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c 'cd /squad-out/squad_raw/ && /snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-quantize \
			--input_dlc=/output/mobilebert_float.dlc \
			--input_list=/squad-out/squad_raw/input_list.txt \
			--weights_bitwidth 8 \
			--act_bitwidth 8 \
			--enable_htp \
			--htp_socs sm7325,sm8350 \
			--use_encoding_optimizations \
			--output_dlc=/output/mobilebert_quantized_htp.dlc'
	@touch $@

gen-hta-dlc-info: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		hta-dlc
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/dlc \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c '\
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info -i /dlc/mobilenet_edgetpu_224_1.0_hta.dlc && \
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info -i /dlc/ssd_mobilenet_v2_qat_hta.dlc && \
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info -i /dlc/deeplabv3_hta.dlc'

gen-htp-dlc-info: \
		${BUILDDIR}/mlperf_mobile_docker_1_0.stamp ${BUILDDIR}/datasets.stamp \
		htp-dlc
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/dlc \
		-u ${USERID}:${GROUPID} \
		mlcommons/mlperf_mobile:1.0 \
		/bin/bash -c '\
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info -i /dlc/mobilenet_edgetpu_224_1.0_htp.dlc && \
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info -i /dlc/ssd_mobiledet_qat_htp.dlc && \
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info -i /dlc/deeplabv3_htp.dlc && \
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info -i /dlc/mobilenet_edgetpu_224_1.0_htp_batched.dlc'

test: ${BUILDDIR}/mlperf_snpe${OSVER}_docker_image.stamp
	@docker run \
		-e PYTHONPATH=/snpe_sdk/lib/python \
		-e LD_LIBRARY_PATH=/snpe_sdk/lib/x86_64-linux-clang \
		-v ${SNPE_SDK}:/snpe_sdk \
		-v ${DLCBUILDDIR}:/dlc \
		-u ${USERID}:${GROUPID} \
		mlperf_snpe${OSVER}:latest \
		/bin/bash -c '\
			/snpe_sdk/bin/x86_64-linux-clang/snpe-dlc-info'

clean:
	@rm -rf ${BUILDDIR}/DLC

